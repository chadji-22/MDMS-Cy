<?php
/**
 * B7 · DSO / officer / TSO · Events, and a tamper alert entered by the DSO
 * [project.pdf §2.4 p.8; §II.Γ-Δ p.3; UC-14]   sp_GetEvents, sp_RaiseTamperEvent (TR20 creates the field job)
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, Ui, Validate, View};

Auth::requireRole('DSO', 'SYSTEM_OFFICER', 'TSO');

const SIZE = 50;
const SEVERITIES = ['INFO', 'WARNING', 'CRITICAL'];
const TYPES = ['COMMAND_FAILED', 'DUPLICATE_READING', 'FREQUENCY_DEVIATION', 'PACKET_COMM_ERROR', 'PACKET_QUARANTINED', 'PACKET_UNMATCHED',
               'PHASE_UNBALANCE', 'TAMPER_ALERT', 'TECHNICAL_LOSS_HIGH', 'THRESHOLD_EXCEEDED', 'UNSUPPORTED_OBIS', 'VOLTAGE_SAG', 'VOLTAGE_SWELL'];

$error = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    Auth::requireRole('DSO');                                  // the procedure says the same
    try {
        $network = Validate::code(Validate::post('network_id'), 60);
        if ($network === null) {
            throw Ui::invalid('give the network id of the meter.');
        }
        $r = Db::row('sp_RaiseTamperEvent', [$network, Db::nv(Validate::note(Validate::post('description'), 500), 500)]);
        View::flash('ok', 'Tamper alert recorded (event ' . (int) ($r['event_id'] ?? 0) . ')'
            . (($r['work_order_id'] ?? null) !== null ? ', work order ' . (int) $r['work_order_id'] . ' created.' : '.'));
        Ui::redirect('/dso/events.php');
    } catch (DbError $e) {
        $error = $e;
        http_response_code($e->httpStatus());
    }
}
$type = in_array(Ui::get('type'), TYPES, true) ? Ui::get('type') : '';
$severity = in_array(Ui::get('severity'), SEVERITIES, true) ? Ui::get('severity') : '';
$from = Validate::date(Ui::get('from'));
$to = Validate::date(Ui::get('to'));
$page = Validate::int(Ui::get('page'), 1, 100000) ?? 1;
$rows = Db::rows('sp_GetEvents', [$type === '' ? null : $type, $severity === '' ? null : $severity,
    $from === null ? null : $from . ' 00:00:00', $to === null ? null : $to . ' 23:59:59', $page, SIZE]);

View::header('Events');
if ($error) {
    View::error($error);
}
?>
<form method="get" action="<?= View::base() ?>/dso/events.php" class="filters">
  <label>Type <select name="type"><?= Ui::options(['' => 'All'] + array_combine(TYPES, TYPES), $type) ?></select></label>
  <label>Severity <select name="severity"><?= Ui::options(['' => 'All'] + array_combine(SEVERITIES, SEVERITIES), $severity) ?></select></label>
  <label>From <input type="date" name="from" value="<?= View::h($from) ?>"></label>
  <label>To (included) <input type="date" name="to" value="<?= View::h($to) ?>"></label>
  <button type="submit">Show</button>
</form>
<?php if ($rows === []): ?>
  <p class="flash">No events for these filters.</p>
<?php else: ?>
  <div class="table-wrap"><table>
    <thead><tr><th>Time (UTC)</th><th>Event</th><th>Severity</th><th>Meter</th><th>Transformer</th><th>Description</th><th class="num">Packet</th><th class="num">Job</th></tr></thead>
    <tbody><?php foreach ($rows as $r): ?>
      <tr><td class="mono"><?= View::h(Ui::ts($r['event_timestamp'])) ?></td><td><?= View::h($r['event_type']) ?></td><td><?= Ui::badge((string) $r['severity']) ?></td>
        <td><?= View::h($r['serial_number'] ?? '—') ?></td><td><?= View::h($r['transformer_name'] ?? '—') ?></td><td><?= View::h($r['description']) ?></td>
        <td class="num"><?= $r['packet_id'] === null ? '—' : (int) $r['packet_id'] ?></td><td class="num"><?= $r['work_order_id'] === null ? '—' : (int) $r['work_order_id'] ?></td></tr>
    <?php endforeach; ?></tbody>
  </table></div>
<?php endif; ?>
<?= Ui::pager('/dso/events.php', ['type' => $type, 'severity' => $severity, 'from' => $from, 'to' => $to], $page, count($rows), SIZE) ?>

<?php if (Auth::role() === 'DSO'): ?>
<h2>Report a tamper alert</h2>
<form method="post" action="<?= View::base() ?>/dso/events.php" class="card">
  <?= Csrf::field() ?>
  <label>Network id of the meter <input name="network_id" maxlength="60" required></label>
  <label>Description (optional) <textarea name="description" rows="3" maxlength="500"></textarea></label>
  <button type="submit">Record the alert</button>
</form>
<p class="muted">An anti-tamper job for a technician is created automatically.</p>
<?php endif; ?>
<?php
View::footer();
