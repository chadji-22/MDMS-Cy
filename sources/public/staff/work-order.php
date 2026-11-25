<?php
declare(strict_types=1);

require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, View};

Auth::requireRole('SYSTEM_ADMIN', 'SYSTEM_OFFICER');
$isPost = $_SERVER['REQUEST_METHOD'] === 'POST';
$isOfficer = Auth::role() === 'SYSTEM_OFFICER';
if ($isPost) {
    Auth::requireRole('SYSTEM_OFFICER');
    Csrf::verify();
}

$intOptions = ['options' => ['min_range' => 1, 'max_range' => 2147483647]];
$workOrderId = filter_input(INPUT_GET, 'id', FILTER_VALIDATE_INT, $intOptions);
if (!$workOrderId) {
    View::fail(400, 'Invalid work order', 'Select a job from Work orders.');
}

try {
    $order = Db::row('sp_ListWorkOrders', [null, null, null, 1, 1, $workOrderId]);
} catch (DbError $error) {
    View::fail($error->httpStatus(), 'Work order unavailable', $error->getUserMessage());
}
if ($order === null) {
    View::fail(404, 'Work order unavailable', 'The work order could not be found.');
}

$path = View::url('/staff/work-order.php?id=' . $workOrderId);   // full URL path (base included)
$canAssign = $isOfficer && $order['status'] === 'SUBMITTED' && $order['district'] !== null;
$source = $isPost ? INPUT_POST : INPUT_GET;
$date = (string) filter_input($source, 'date');
$start = (string) filter_input($source, 'start');
$end = (string) filter_input($source, 'end');
$hasSearch = $isPost || filter_has_var(INPUT_GET, 'date');
$results = null;
$inputError = null;
$dbError = null;

if ($isPost && !$canAssign) {
    View::fail(409, 'Assignment unavailable', 'Only a submitted work order with a district can be assigned.');
}

if ($hasSearch && $canAssign) {
    $validDate = preg_match('/\A([0-9]{4})-([0-9]{2})-([0-9]{2})\z/', $date, $parts) === 1
        && checkdate((int) $parts[2], (int) $parts[3], (int) $parts[1]);
    $timePattern = '/\A(?:[01][0-9]|2[0-3]):[0-5][0-9]\z/';
    if (!$validDate || preg_match($timePattern, $start) !== 1 || preg_match($timePattern, $end) !== 1 || $end <= $start) {
        $inputError = 'Choose a visit date and an end time after the start time.';
    } else {
        try {
            if ($isPost) {
                $technicianId = filter_input(INPUT_POST, 'technician_id', FILTER_VALIDATE_INT, $intOptions);
                if (!$technicianId) {
                    View::fail(400, 'Invalid technician', 'Select an available technician for this visit.');
                }
                Db::callAsActor('sp_AssignWorkOrder', [$workOrderId, $technicianId, $date . 'T' . $start . ':00', $date . 'T' . $end . ':00']);
                View::flash('ok', 'Work order assigned.');
                header('Location: ' . $path, true, 303);
                exit;
            }
            $results = Db::rows('sp_FindAvailableTechnicians', [$date, $start, $end, Db::nv($order['district'], 30)]);
        } catch (DbError $error) {
            $dbError = $error;
        }
    }
}

View::header('Work order #' . $workOrderId);
?>
<p><a href="<?= View::base() ?>/staff/work-orders.php">Back to Work orders</a></p>
<dl>
    <dt>Type</dt><dd><?= View::h($order['work_type']) ?></dd>
    <dt>Status</dt><dd><?= View::h($order['status']) ?></dd>
    <dt>Description</dt><dd><?= View::h($order['description'] ?? '—') ?></dd>
    <dt>Premise</dt><dd><?= View::h($order['premise_address'] ?? '—') ?></dd>
    <dt>District</dt><dd><?= View::h($order['district'] ?? '—') ?></dd>
    <dt>Technician</dt><dd><?= View::h($order['technician_name'] ?? '—') ?></dd>
    <dt>Visit (UTC)</dt><dd><?= View::h($order['scheduled_start'] ?? '—') ?><?php if ($order['scheduled_end'] !== null): ?>
        to <?= View::h($order['scheduled_end']) ?><?php endif; ?></dd>
</dl>
<?php if ($inputError !== null): ?>
    <p class="flash error" role="alert"><?= View::h($inputError) ?></p>
<?php endif; ?>
<?php if ($dbError !== null): ?>
    <?php View::error($dbError); ?>
<?php endif; ?>
<?php if ($canAssign): ?>
    <h2>Find available technicians</h2>
    <form method="get" action="<?= View::base() ?>/staff/work-order.php" class="card">
        <input type="hidden" name="id" value="<?= View::h($workOrderId) ?>">
        <label>Visit date <input type="date" name="date" value="<?= View::h($date) ?>" required></label>
        <label>Start (UTC) <input type="time" name="start" value="<?= View::h($start) ?>" required></label>
        <label>End (UTC) <input type="time" name="end" value="<?= View::h($end) ?>" required></label>
        <button type="submit">Find technicians</button>
    </form>
    <?php if ($results === []): ?>
        <p>No technicians are available in this district for the selected time.</p>
    <?php elseif ($results !== null): ?>
        <table>
            <thead><tr><th>Technician</th><th>Specialty</th><th>Action</th></tr></thead>
            <tbody>
            <?php foreach ($results as $technician): ?>
                <tr>
                    <td><?= View::h($technician['full_name']) ?></td>
                    <td><?= View::h($technician['specialty']) ?></td>
                    <td>
                        <form method="post" action="<?= View::h($path) ?>">
                            <?= Csrf::field() ?>
                            <input type="hidden" name="technician_id" value="<?= View::h($technician['user_id']) ?>">
                            <input type="hidden" name="date" value="<?= View::h($date) ?>">
                            <input type="hidden" name="start" value="<?= View::h($start) ?>">
                            <input type="hidden" name="end" value="<?= View::h($end) ?>">
                            <button type="submit">Assign</button>
                        </form>
                    </td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table>
    <?php endif; ?>
<?php elseif ($isOfficer && $order['status'] === 'SUBMITTED'): ?>
    <p>This work order needs a premise district before it can be assigned.</p>
<?php endif; ?>
<?php View::footer(); ?>
