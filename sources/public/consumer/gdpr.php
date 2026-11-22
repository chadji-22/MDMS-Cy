<?php
/**
 * B3 · Consumer · Privacy: right to be forgotten and retention reduction
 * [project.pdf §1.4 p.6: the consumer submits a right-to-be-forgotten request; it is not an immediate delete but goes
 *  through submission, review, pre-approval and final approval, each stage logged (date, action, user);
 *  §1.4 p.6-7: through an approved request the raw 15-minute readings of a meter are kept 1 month instead of 3 years]
 * Procedures: sp_SubmitGdprRequest, sp_ListGdprRequests (the consumer sees their own, with the history of stages).
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';
require __DIR__ . '/../../areas/consumer/lib.php';

use Mdms\{Auth, Csrf, Db, DbError, View};
use Mdms\Consumer as C;

Auth::requireRole('CONSUMER');

const REQUEST_TYPES = ['RETENTION_REDUCTION' => 'Keep the raw readings of one meter for 1 month only',
                       'RIGHT_TO_BE_FORGOTTEN' => 'Right to be forgotten (anonymize my account)'];

$error = null;
$type = (string) ($_POST['request_type'] ?? 'RETENTION_REDUCTION');

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    try {
        $meterId = null;
        if ($type === 'RETENTION_REDUCTION') {
            $premise = C\premise(ctype_digit((string) ($_POST['premise_id'] ?? '')) ? (int) $_POST['premise_id'] : null);
            $meterId = isset($premise['meter_id']) ? (int) $premise['meter_id'] : null;
            if ($meterId === null) {
                throw new DbError(DbError::INPUT, 50004, 422, 'Invalid input: choose a premise that has a meter in service.');
            }
        } elseif (!isset($_POST['confirm'])) {
            throw new DbError(DbError::INPUT, 50004, 422, 'Please tick the box to confirm that you understand what the right to be forgotten does.');
        }
        $res = Db::rows('sp_SubmitGdprRequest', [$type, $meterId]);
        View::flash('ok', 'Request #' . (int) ($res[0]['gdpr_request_id'] ?? 0) . ' submitted. Officers review it; every stage is listed below.');
        header('Location: /consumer/gdpr.php', true, 303);
        exit;
    } catch (DbError $e) {
        $error = $e;
    }
}

$requests = Db::rows('sp_ListGdprRequests', [null, 1, 100]);
$withMeter = array_values(array_filter(C\premises(), static fn (array $p): bool => $p['meter_id'] !== null));

View::header('Privacy (GDPR)');
if ($error) {
    View::error($error);
}
?>
<p>A request is never carried out at once: an officer reviews it, pre-approves it, and a second officer gives the final
  approval. Only then is it executed. Bills and payments are kept for accounting, and daily / monthly / yearly totals
  remain.</p>

<form method="post" action="/consumer/gdpr.php" class="card wide">
  <?= Csrf::field() ?>
  <h2>New request</h2>
  <label>Request <select name="request_type"><?= C\options(REQUEST_TYPES, $type) ?></select></label>
  <label>Meter (for the retention request) <select name="premise_id">
    <?php foreach ($withMeter as $p): ?>
      <option value="<?= (int) $p['premise_id'] ?>"><?= View::h('Meter ' . $p['serial_number'] . ' · premise #' . $p['premise_id'] . ' ' . $p['address']) ?></option>
    <?php endforeach; ?></select></label>
  <label class="check"><input type="checkbox" name="confirm" value="1">
    For the right to be forgotten: I understand that my account is anonymized and closed, and that I can no longer log in.</label>
  <button type="submit">Submit request</button>
</form>

<h2>My requests</h2>
<?php if ($requests === []): ?>
  <p class="muted">No requests yet.</p>
<?php else: ?>
  <div class="table-wrap"><table>
    <thead><tr><th>#</th><th>Type</th><th>Status</th><th>Submitted (UTC)</th><th>Decided</th><th>Meter</th><th>History of stages</th></tr></thead>
    <tbody>
    <?php foreach ($requests as $g): ?>
      <tr><td><?= (int) $g['gdpr_request_id'] ?></td><td><?= View::h($g['request_type']) ?></td>
        <td><span class="badge"><?= View::h($g['status']) ?></span></td>
        <td class="mono"><?= View::h(C\ts($g['submitted_at'])) ?></td><td class="mono"><?= View::h(C\ts($g['decided_at'])) ?></td>
        <td><?= $g['meter_id'] === null ? '—' : (int) $g['meter_id'] ?></td>
        <td><?php foreach (array_filter(explode('; ', (string) $g['history'])) as $line): ?><div class="mono small"><?= View::h($line) ?></div><?php endforeach; ?></td></tr>
    <?php endforeach; ?>
    </tbody>
  </table></div>
<?php endif; ?>
<?php
View::footer();
