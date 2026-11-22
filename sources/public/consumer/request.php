<?php
/**
 * B3 · Consumer · One request: its status and history; cancel while it is still SUBMITTED
 * [project.pdf §1.3 p.6: the request has a status and a history and is followed until completion;
 *  Κοινές αρχές p.5: every change is traceable (who, when, old / new state)]
 * Procedures: sp_GetWorkOrderHistory (the AUDIT_LOG rows of the work order), sp_CancelWorkOrder.
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';
require __DIR__ . '/../../areas/consumer/lib.php';

use Mdms\{Auth, Csrf, Db, DbError, View};
use Mdms\Consumer as C;

Auth::requireRole('CONSUMER');

$raw = (string) ($_POST['id'] ?? $_GET['id'] ?? '');
$id = ctype_digit($raw) ? (int) $raw : 0;
$error = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    try {
        $reason = trim((string) ($_POST['reason'] ?? ''));
        Db::callAsActor('sp_CancelWorkOrder', [$id, Db::nv($reason === '' ? 'Cancelled by the consumer' : $reason, 500)]);
        View::flash('ok', 'Request #' . $id . ' cancelled.');
        header('Location: /consumer/request.php?id=' . $id, true, 303);
        exit;
    } catch (DbError $e) {
        $error = $e;
    }
}

$rows = [];
try {
    $rows = Db::rows('sp_GetWorkOrderHistory', [$id]);      // 50001 unknown id, 50002 someone else's request
} catch (DbError $e) {
    $error ??= $e;
}
$wo = $rows[0] ?? null;

View::header('Request #' . $id);
if ($error) {
    View::error($error);
}
if ($wo !== null):
?>
<div class="card wide">
  <p><strong><?= View::h($wo['work_type']) ?></strong> · status <span class="badge"><?= View::h($wo['current_status']) ?></span>
    · origin <?= View::h($wo['origin']) ?></p>
  <p><?= View::h($wo['description']) ?></p>
  <?php if ($wo['scheduled_start'] !== null): ?><p>Visit: <?= View::h(C\ts($wo['scheduled_start'])) ?> – <?= View::h(C\ts($wo['scheduled_end'])) ?> (UTC)</p><?php endif; ?>
  <?php if ($wo['findings'] !== null): ?><p>Findings: <?= View::h($wo['findings']) ?></p><?php endif; ?>
  <?php if ($wo['current_status'] === 'SUBMITTED'): ?>
    <form method="post" action="/consumer/request.php" class="row">
      <?= Csrf::field() ?>
      <input type="hidden" name="id" value="<?= $id ?>">
      <label>Reason <input name="reason" maxlength="500" placeholder="optional"></label>
      <button type="submit" class="secondary">Cancel the request</button>
    </form>
  <?php endif; ?>
</div>

<h2>History</h2>
<div class="table-wrap"><table>
  <thead><tr><th>When (UTC)</th><th>Action</th><th>From</th><th>To</th><th>By</th><th>Comment</th></tr></thead>
  <tbody>
  <?php foreach ($rows as $h): if ($h['logged_at'] === null) { continue; } ?>
    <tr><td class="mono"><?= View::h(C\ts($h['logged_at'])) ?></td><td><?= View::h($h['action']) ?></td>
      <td><?= View::h($h['old_state']) ?></td><td><?= View::h($h['new_state']) ?></td>
      <td><?= View::h($h['actor_name'] ?? $h['mechanism'] ?? $h['actor_type']) ?></td><td><?= View::h($h['comment']) ?></td></tr>
  <?php endforeach; ?>
  </tbody>
</table></div>
<?php endif; ?>
<p><a href="/consumer/requests.php">Back to my requests</a></p>
<?php
View::footer();
