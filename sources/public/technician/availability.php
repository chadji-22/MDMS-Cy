<?php
declare(strict_types=1);

require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, View};

Auth::requireRole('TECHNICIAN');

$districts = ['Λευκωσία', 'Λεμεσός', 'Λάρνακα', 'Πάφος', 'Αμμόχωστος', 'Κερύνεια'];
$today = gmdate('Y-m-d');
$date = $today;
$start = '';
$end = '';
$district = '';
$slots = [];
$formError = null;
$requestError = null;
$listError = null;
$timePattern = '/\A(?:[01][0-9]|2[0-3]):[0-5][0-9](?::[0-5][0-9])?\z/';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    $action = filter_input(INPUT_POST, 'action');
    if (!in_array($action, ['save', 'remove'], true)) {
        View::fail(400, 'Invalid action', 'Reload Availability and try again.');
    }

    $slotDate = (string) filter_input(INPUT_POST, 'avail_date');
    $slotStart = (string) filter_input(INPUT_POST, 'start_time');
    $parsedDate = preg_match('/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/', $slotDate) === 1
        ? DateTimeImmutable::createFromFormat('!Y-m-d', $slotDate)
        : false;
    $validSlotKey = $parsedDate !== false && $parsedDate->format('Y-m-d') === $slotDate
        && preg_match($timePattern, $slotStart) === 1;

    if ($action === 'save') {
        $date = $slotDate;
        $start = $slotStart;
        $end = (string) filter_input(INPUT_POST, 'end_time');
        $district = (string) filter_input(INPUT_POST, 'district');

        if (!$validSlotKey || $date < $today || preg_match($timePattern, $end) !== 1
            || str_pad($end, 8, ':00') <= str_pad($start, 8, ':00') || !in_array($district, $districts, true)) {
            $formError = 'Choose a date from today onward, a district, and an end time after the start.';
        }
    } elseif (!$validSlotKey) {
        View::fail(400, 'Invalid availability slot', 'Reload Availability and try again.');
    }

    if ($formError === null) {
        try {
            if ($action === 'save') {
                Db::callAsActor('sp_SetAvailability', [$date, $start, $end, Db::nv($district, 30)]);
                View::flash('ok', 'Availability saved.');
            } else {
                Db::callAsActor('sp_DeleteAvailability', [$slotDate, $slotStart]);
                View::flash('ok', 'Availability removed.');
            }
            header('Location: /technician/availability.php', true, 303);
            exit;
        } catch (DbError $error) {
            $requestError = $error;
        }
    }
}

try {
    $slots = Db::rows('sp_GetMyAvailability');
} catch (DbError $error) {
    $listError = $error;
}

View::header('Availability');
if ($requestError !== null) {
    View::error($requestError);
}
?>
<h2>Add or update a slot</h2>
<form method="post" action="/technician/availability.php" class="card">
    <?= Csrf::field() ?>
    <input type="hidden" name="action" value="save">
    <?php if ($formError !== null): ?>
        <p class="flash error" role="alert"><?= View::h($formError) ?></p>
    <?php endif; ?>
    <label>Date <input type="date" name="avail_date" min="<?= View::h($today) ?>" value="<?= View::h($date) ?>" required></label>
    <label>Start (UTC) <input type="time" name="start_time" step="1" value="<?= View::h($start) ?>" required></label>
    <label>End (UTC) <input type="time" name="end_time" step="1" value="<?= View::h($end) ?>" required></label>
    <label>District
        <select name="district" required>
            <option value="">Select a district</option>
            <?php foreach ($districts as $option): ?>
                <option value="<?= View::h($option) ?>" <?= $district === $option ? 'selected' : '' ?>><?= View::h($option) ?></option>
            <?php endforeach; ?>
        </select>
    </label>
    <button type="submit">Save availability</button>
</form>

<h2>My availability</h2>
<?php if ($listError !== null): ?>
    <?php View::error($listError); ?>
<?php elseif ($slots === []): ?>
    <p>No availability declared.</p>
<?php else: ?>
    <table>
        <thead><tr><th>Date</th><th>Start (UTC)</th><th>End (UTC)</th><th>District</th><th>Actions</th></tr></thead>
        <tbody>
        <?php foreach ($slots as $slot): ?>
            <?php $slotStart = substr($slot['start_time'], 0, 8); ?>
            <tr>
                <td><?= View::h($slot['avail_date']) ?></td>
                <td><?= View::h($slotStart) ?></td>
                <td><?= View::h(substr($slot['end_time'], 0, 8)) ?></td>
                <td><?= View::h($slot['district']) ?></td>
                <td>
                    <form method="post" action="/technician/availability.php">
                        <?= Csrf::field() ?>
                        <input type="hidden" name="action" value="remove">
                        <input type="hidden" name="avail_date" value="<?= View::h($slot['avail_date']) ?>">
                        <input type="hidden" name="start_time" value="<?= View::h($slotStart) ?>">
                        <button type="submit">Remove</button>
                    </form>
                </td>
            </tr>
        <?php endforeach; ?>
        </tbody>
    </table>
<?php endif; ?>
<?php View::footer(); ?>
