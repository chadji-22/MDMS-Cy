<?php
/**
 * B3 · Consumer · Meter check and fault requests (submit and list)
 * [project.pdf §1.3 p.6: the consumer asks for a meter check or reports a fault for a premise / meter; the request gets
 *  a status and a history, so that it can be assigned to a field technician and followed until it is completed]
 * Procedures: sp_SubmitServiceRequest, sp_ListMyWorkOrders (consumer branch: own requests, any status).
 * Detail and history: request.php.
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';
require __DIR__ . '/../../areas/consumer/lib.php';

use Mdms\{Auth, Csrf, Db, DbError, View};
use Mdms\Consumer as C;

Auth::requireRole('CONSUMER');

const WORK_TYPES = ['FAULT_REPAIR' => 'Fault report', 'TECHNICAL_CHECK' => 'Meter check (fee applies)'];

$premiseId = C\selectedPremiseId();
$form = ['work_type' => (string) ($_POST['work_type'] ?? 'FAULT_REPAIR'), 'description' => trim((string) ($_POST['description'] ?? ''))];
$error = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    try {
        if ($form['description'] === '') {
            throw new DbError(DbError::INPUT, 50004, 422, 'Invalid input: describe the problem or the reason for the check.');
        }
        // meter NULL: the procedure uses the meter in service on the premise
        $res = Db::rows('sp_SubmitServiceRequest', [(int) $premiseId, null, $form['work_type'], Db::nv($form['description'], 1000)]);
        $id = (int) ($res[0]['work_order_id'] ?? 0);
        View::flash('ok', 'Request #' . $id . ' submitted. An officer assigns it to a technician; you can follow it here.');
        header('Location: ' . View::url('/consumer/request.php?id=') . $id, true, 303);
        exit;
    } catch (DbError $e) {
        $error = $e;
    }
}

$requests = Db::rows('sp_ListMyWorkOrders', [null, 1, 100]);

View::header('Check and fault requests');
if ($error) {
    View::error($error);
}
if (C\premises() === []) {
    C\noPremiseNotice();
} else {
?>
<form method="post" action="<?= View::base() ?>/consumer/requests.php" class="card wide">
  <?= Csrf::field() ?>
  <h2>New request</h2>
  <div class="row">
    <label>Premise <select name="premise_id"><?= C\premiseOptions($premiseId) ?></select></label>
    <label>Type <select name="work_type"><?= C\options(WORK_TYPES, $form['work_type']) ?></select></label>
  </div>
  <label>Description <textarea name="description" required maxlength="1000" rows="3"><?= View::h($form['description']) ?></textarea></label>
  <p class="muted">A meter check has the MDMS-Cy fee shown on <a href="<?= View::base() ?>/consumer/bills.php">Bills and payments</a>.</p>
  <button type="submit">Submit request</button>
</form>
<?php } ?>

<h2>My requests</h2>
<?php if ($requests === []): ?>
  <p class="muted">No requests yet.</p>
<?php else: ?>
  <div class="table-wrap"><table>
    <thead><tr><th>#</th><th>Type</th><th>Status</th><th>Submitted (UTC)</th><th>Premise</th><th>Visit</th><th>Technician</th><th></th></tr></thead>
    <tbody>
    <?php foreach ($requests as $r): $id = (int) $r['work_order_id']; ?>
      <tr><td><?= $id ?></td><td><?= View::h(WORK_TYPES[$r['work_type']] ?? $r['work_type']) ?></td>
        <td><span class="badge"><?= View::h($r['status']) ?></span></td>
        <td class="mono"><?= View::h(C\ts($r['created_at'])) ?></td>
        <td>#<?= (int) $r['premise_id'] ?> <?= View::h($r['premise_address']) ?></td>
        <td class="mono"><?= View::h(C\ts($r['scheduled_start'])) ?></td>
        <td><?= View::h($r['technician_name'] ?? '—') ?></td>
        <td><a href="<?= View::base() ?>/consumer/request.php?id=<?= $id ?>">History</a></td></tr>
    <?php endforeach; ?>
    </tbody>
  </table></div>
<?php endif; ?>
<?php
View::footer();
