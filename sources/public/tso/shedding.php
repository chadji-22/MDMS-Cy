<?php
/**
 * B8 · TSO · Remote shedding (or reconnection) of every active meter under a transformer, and the commands it creates
 * [project.pdf §II.Δ p.3; §2.4 p.8; UC-13]   sp_ShedTransformerLoad, sp_DispatchCommands, sp_ListCommands
 * Two steps: first the page shows what would be affected, then the TSO confirms.
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, Ui, Validate, View};

Auth::requireRole('TSO');

const TYPES = ['DISCONNECT' => 'Disconnect (shed)', 'RECONNECT' => 'Reconnect'];
const STATUSES = ['PENDING_APPROVAL', 'APPROVED', 'REJECTED', 'SENT', 'ACKNOWLEDGED', 'FAILED'];
const SIZE = 50;

$in = ['transformer_id' => Ui::get('transformer_id'), 'command_type' => Ui::get('command_type'), 'reason' => Ui::get('reason')];
$error = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    try {
        if (Validate::post('action') === 'dispatch') {
            $one = Validate::id(Validate::post('command_id'));
            if ($one === null) {
                throw Ui::invalid('choose a command.');
            }
            $r = Db::row('sp_DispatchCommands', [3, $one]);
            View::flash('ok', 'Command ' . $one . ': ' . (int) ($r['attempts_sent'] ?? 0) . ' attempt sent, ' . (int) ($r['commands_failed'] ?? 0) . ' failed (no answer after 3 attempts).');
        } elseif (Validate::post('action') === 'dispatch_all') {
            $r = Db::row('sp_DispatchCommands', [3, null]);
            View::flash('ok', (int) ($r['attempts_sent'] ?? 0) . ' attempts sent, ' . (int) ($r['commands_failed'] ?? 0) . ' commands failed, ' . (int) ($r['errors'] ?? 0) . ' errors.');
        } elseif (Validate::post('action') === 'shed') {
            foreach ($in as $name => $_) {
                $in[$name] = trim(Validate::post($name));
            }
            $id = Validate::id($in['transformer_id']);
            $reason = Validate::note($in['reason'], 400);
            if ($id === null || !isset(TYPES[$in['command_type']]) || $reason === null) {
                throw Ui::invalid('choose a transformer and a command, and give a reason.');
            }
            if (Validate::post('confirm') !== '1') {
                throw Ui::invalid('tick the confirmation first.');
            }
            $r = Db::row('sp_ShedTransformerLoad', [$id, $in['command_type'], Db::nv($reason, 400)]);
            View::flash('ok', (int) ($r['commands_created'] ?? 0) . ' commands were created. They are sent when they are dispatched below.');
        } else {
            throw Ui::invalid('unknown action.');
        }
        Ui::redirect('/tso/shedding.php');
    } catch (DbError $e) {
        $error = $e;
        http_response_code($e->httpStatus());
    }
}
$tree = Db::rows('sp_GetTransformerTree', [null]);
$byId = array_column($tree, null, 'transformer_id');
$chosen = Validate::id($in['transformer_id']);
$ready = $chosen !== null && isset($byId[$chosen], TYPES[$in['command_type']]) && $in['reason'] !== '';
$meters = $ready ? (int) array_sum(array_column(Db::rows('sp_GetTransformerTree', [$chosen]), 'meters_connected')) : 0;

$status = in_array(Ui::get('status'), STATUSES, true) ? Ui::get('status') : '';
$page = Validate::int(Ui::get('page'), 1, 100000) ?? 1;
$commands = Db::rows('sp_ListCommands', [$status === '' ? null : $status, null, $page, SIZE, null]);

View::header('Remote shedding');
if ($error) {
    View::error($error);
}
?>
<form method="get" action="/tso/shedding.php" class="card">
  <h2>1. Choose</h2>
  <label>Transformer <select name="transformer_id" required><?= Ui::options(['' => 'Choose'] + Ui::transformerOptions($tree), $in['transformer_id']) ?></select></label>
  <label>Command <select name="command_type"><?= Ui::options(TYPES, $in['command_type']) ?></select></label>
  <label>Reason <input name="reason" maxlength="400" value="<?= View::h($in['reason']) ?>" required></label>
  <button type="submit" class="secondary">Check what is affected</button>
</form>
<?php if ($ready): ?>
<form method="post" action="/tso/shedding.php" class="card">
  <?= Csrf::field() ?>
  <h2>2. Confirm</h2>
  <p><strong><?= View::h(TYPES[$in['command_type']]) ?></strong> for the active meters under <strong><?= View::h($byId[$chosen]['name']) ?></strong>
    (<?= $meters ?> meters are connected there; only the active ones get a command). All or nothing.</p>
  <p class="muted">Reason: <?= View::h($in['reason']) ?></p>
  <?php foreach ($in as $name => $v): ?><input type="hidden" name="<?= View::h($name) ?>" value="<?= View::h($v) ?>"><?php endforeach; ?>
  <label class="check"><input type="checkbox" name="confirm" value="1" required> I confirm the command for all these meters</label>
  <button type="submit" name="action" value="shed">Create the commands</button>
</form>
<?php endif; ?>

<h2>Commands</h2>
<form method="get" action="/tso/shedding.php" class="filters">
  <label>Status <select name="status"><?= Ui::options(['' => 'All'] + array_combine(STATUSES, STATUSES), $status) ?></select></label>
  <button type="submit" class="secondary">Show</button>
</form>
<form method="post" action="/tso/shedding.php">
  <?= Csrf::field() ?>
  <p><button type="submit" name="action" value="dispatch_all">Dispatch every waiting command</button>
    <span class="muted small">Includes the approved commands of officers and the DSO. After 3 attempts without an answer a command fails.</span></p>
</form>
<?php if ($commands === []): ?>
  <p class="flash">No commands.</p>
<?php else: ?>
<div class="table-wrap"><table>
  <thead><tr><th class="num">No.</th><th>Meter</th><th>Command</th><th>Details</th><th>Status</th><th>Requested (UTC)</th><th class="num">Attempts</th><th>Answer (UTC)</th><th>Result</th><th></th></tr></thead>
  <tbody><?php foreach ($commands as $c): ?>
    <tr><td class="num"><?= (int) $c['command_id'] ?></td><td><?= View::h($c['serial_number']) ?></td><td><?= View::h($c['command_type']) ?></td>
      <td><?= View::h($c['parameters']) ?></td><td><?= Ui::badge((string) $c['status']) ?></td><td class="mono"><?= View::h(Ui::ts($c['requested_at'])) ?></td>
      <td class="num"><?= (int) $c['attempt_count'] ?></td><td class="mono"><?= View::h(Ui::ts($c['ack_at'])) ?></td><td><?= View::h($c['result']) ?></td>
      <td><?php if (in_array($c['status'], ['APPROVED', 'SENT'], true)): ?>
        <form method="post" action="/tso/shedding.php" class="inline"><?= Csrf::field() ?>
          <input type="hidden" name="command_id" value="<?= (int) $c['command_id'] ?>">
          <button type="submit" name="action" value="dispatch" class="secondary">Dispatch</button></form><?php endif; ?></td></tr>
  <?php endforeach; ?></tbody>
</table></div>
<?php endif; ?>
<?= Ui::pager('/tso/shedding.php', ['status' => $status], $page, count($commands), SIZE) ?>
<?php
View::footer();
