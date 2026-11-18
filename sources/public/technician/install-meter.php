<?php
declare(strict_types=1);

require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, View};

Auth::requireRole('TECHNICIAN');

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
}

$intOptions = ['options' => ['min_range' => 1, 'max_range' => 2147483647]];
$jobId = filter_input(INPUT_GET, 'id', FILTER_VALIDATE_INT, $intOptions);
if ($jobId === false || $jobId === null) {
    View::fail(400, 'Invalid job', 'Select an installation job from My Jobs.');
}

try {
    $job = Db::row('sp_GetWorkOrderHistory', [$jobId]);
} catch (DbError $error) {
    View::fail($error->httpStatus(), 'Job unavailable', $error->getUserMessage());
}

if ($job === null || $job['work_type'] !== 'INSTALLATION'
    || !in_array($job['current_status'], ['ACCEPTED', 'IN_PROGRESS'], true)) {
    View::fail(400, 'Installation unavailable', 'Accept an installation job before registering its meter.');
}

$fields = ['serial_number' => '', 'network_id' => '', 'firmware_version' => '', 'communication_type' => '',
    'latitude' => '', 'longitude' => '', 'meter_type_id' => '', 'transformer_id' => ''];
$communications = ['CELLULAR', 'NB_IOT', 'PLC'];
$formError = null;
$dbError = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    foreach ($fields as $name => $value) {
        $fields[$name] = trim((string) filter_input(INPUT_POST, $name));
    }

    $latitude = filter_var($fields['latitude'], FILTER_VALIDATE_FLOAT);
    $longitude = filter_var($fields['longitude'], FILTER_VALIDATE_FLOAT);
    $meterType = filter_var($fields['meter_type_id'], FILTER_VALIDATE_INT, $intOptions);
    $transformer = $fields['transformer_id'] === '' ? null
        : filter_var($fields['transformer_id'], FILTER_VALIDATE_INT, $intOptions);

    if (preg_match('/\A[ -~]{1,50}\z/', $fields['serial_number']) !== 1
        || preg_match('/\A[ -~]{1,60}\z/', $fields['network_id']) !== 1
        || preg_match('/\A[ -~]{1,30}\z/', $fields['firmware_version']) !== 1
        || !in_array($fields['communication_type'], $communications, true)
        || $latitude === false || $latitude < -90 || $latitude > 90
        || $longitude === false || $longitude < -180 || $longitude > 180
        || $meterType === false || $transformer === false) {
        $formError = 'Enter valid meter identifiers, firmware, communication type, coordinates and IDs.';
    } else {
        try {
            $meter = Db::row('sp_InstallMeter', [
                $jobId, $fields['serial_number'], $fields['network_id'], $fields['firmware_version'],
                $fields['communication_type'], $latitude, $longitude, $meterType, null, $transformer,
            ]);
            View::flash('ok', 'Meter #' . $meter['meter_id'] . ' registered and pending approval.');
            header('Location: /technician/', true, 303);
            exit;
        } catch (DbError $error) {
            $dbError = $error;
        }
    }
}

View::header('Register meter for job #' . $jobId);
?>
<p><a href="/technician/">Back to My Jobs</a></p>
<?php if ($formError !== null): ?>
    <p class="flash error" role="alert"><?= View::h($formError) ?></p>
<?php endif; ?>
<?php if ($dbError !== null): ?>
    <?php View::error($dbError); ?>
<?php endif; ?>
<form method="post" action="/technician/install-meter.php?id=<?= View::h($jobId) ?>" class="card">
    <?= Csrf::field() ?>
    <label>Serial number <input name="serial_number" maxlength="50" value="<?= View::h($fields['serial_number']) ?>" required></label>
    <label>Network ID <input name="network_id" maxlength="60" value="<?= View::h($fields['network_id']) ?>" required></label>
    <label>Firmware version <input name="firmware_version" maxlength="30" value="<?= View::h($fields['firmware_version']) ?>" required></label>
    <label>Communication type
        <select name="communication_type" required>
            <option value="">Select a type</option>
            <?php foreach ($communications as $type): ?>
                <option value="<?= View::h($type) ?>" <?= $fields['communication_type'] === $type ? 'selected' : '' ?>><?= View::h($type) ?></option>
            <?php endforeach; ?>
        </select>
    </label>
    <label>Latitude <input name="latitude" type="number" min="-90" max="90" step="0.000001" value="<?= View::h($fields['latitude']) ?>" required></label>
    <label>Longitude <input name="longitude" type="number" min="-180" max="180" step="0.000001" value="<?= View::h($fields['longitude']) ?>" required></label>
    <label>Meter type ID <input name="meter_type_id" type="number" min="1" value="<?= View::h($fields['meter_type_id']) ?>" required></label>
    <label>Transformer ID (optional) <input name="transformer_id" type="number" min="1" value="<?= View::h($fields['transformer_id']) ?>" aria-describedby="transformer-help"></label>
    <small id="transformer-help">Leave blank to look up the transformer from the coordinates.</small>
    <button type="submit">Register meter</button>
</form>
<?php View::footer(); ?>
