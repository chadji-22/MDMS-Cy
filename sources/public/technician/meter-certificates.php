<?php
declare(strict_types=1);

require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, View};

Auth::requireRole('TECHNICIAN');

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
}

$meterId = filter_input(INPUT_GET, 'id', FILTER_VALIDATE_INT, [
    'options' => ['min_range' => 1, 'max_range' => 2147483647],
]);
if ($meterId === false || $meterId === null) {
    View::fail(400, 'Invalid meter', 'Select a meter from My Jobs.');
}

try {
    $meterRows = Db::rows('sp_GetMeter', [$meterId]);
} catch (DbError $error) {
    View::fail($error->httpStatus(), 'Meter unavailable', $error->getUserMessage());
}

if ($meterRows === []) {
    View::fail(404, 'Meter unavailable', 'The meter could not be found.');
}

$types = [
    'CALIBRATION_CERT' => 'Calibration certificate',
    'CE_DECLARATION' => 'CE declaration',
    'ENCRYPTION_CERT' => 'Encryption certificate',
];
$type = $code = $issued = $expires = '';
$formError = null;
$dbError = null;
$path = '/technician/meter-certificates.php?id=' . $meterId;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $type = (string) filter_input(INPUT_POST, 'doc_type');
    $code = trim((string) filter_input(INPUT_POST, 'doc_code'));
    $issued = (string) filter_input(INPUT_POST, 'issue_date');
    $expires = (string) filter_input(INPUT_POST, 'expiry_date');
    $file = $_FILES['certificate'] ?? null;

    $validDate = static function (string $date): bool {
        return preg_match('/\A([0-9]{4})-([0-9]{2})-([0-9]{2})\z/', $date, $parts) === 1
            && checkdate((int) $parts[2], (int) $parts[3], (int) $parts[1]);
    };

    if (!isset($types[$type]) || preg_match('/\A[ -~]{1,60}\z/', $code) !== 1 || !$validDate($issued)
        || ($expires !== '' && (!$validDate($expires) || $expires < $issued))) {
        $formError = 'Choose a certificate type and enter a code and valid dates.';
    } elseif ($file === null || $file['error'] !== UPLOAD_ERR_OK || $file['size'] < 1 || $file['size'] > 2 * 1024 * 1024
        || !is_uploaded_file($file['tmp_name']) || (new finfo(FILEINFO_MIME_TYPE))->file($file['tmp_name']) !== 'application/pdf') {
        $formError = 'Choose a PDF file no larger than 2 MB.';
    } else {
        $storage = __DIR__ . '/../../var/meter-certificates';
        $name = bin2hex(random_bytes(16)) . '.pdf';
        $destination = $storage . '/' . $name;

        if (!is_dir($storage) || !move_uploaded_file($file['tmp_name'], $destination)) {
            $formError = 'The certificate could not be saved. Contact the application administrator.';
        } else {
            try {
                Db::callAsActor('sp_AddMeterDocument', [
                    $meterId, $type, $code, $issued, $expires === '' ? null : $expires, 'meter-certificates/' . $name,
                ]);
            } catch (DbError $error) {
                unlink($destination);
                $dbError = $error;
            }

            if ($dbError === null) {
                View::flash('ok', 'Certificate uploaded and pending review.');
                header('Location: ' . $path, true, 303);
                exit;
            }
        }
    }
}

View::header('Certificates for meter #' . $meterId);
?>
<p><a href="/technician/">Back to My Jobs</a></p>
<p>Meter serial number: <?= View::h($meterRows[0]['serial_number']) ?></p>
<?php if ($formError !== null): ?>
    <p class="flash error" role="alert"><?= View::h($formError) ?></p>
<?php endif; ?>
<?php if ($dbError !== null): ?>
    <?php View::error($dbError); ?>
<?php endif; ?>
<form method="post" action="<?= View::h($path) ?>" enctype="multipart/form-data" class="card">
    <?= Csrf::field() ?>
    <label>Certificate type
        <select name="doc_type" required>
            <option value="">Select a type</option>
            <?php foreach ($types as $value => $label): ?>
                <option value="<?= View::h($value) ?>" <?= $type === $value ? 'selected' : '' ?>><?= View::h($label) ?></option>
            <?php endforeach; ?>
        </select>
    </label>
    <label>Certificate code <input name="doc_code" maxlength="60" value="<?= View::h($code) ?>" required></label>
    <label>Issue date <input type="date" name="issue_date" value="<?= View::h($issued) ?>" required></label>
    <label>Expiry date (optional) <input type="date" name="expiry_date" value="<?= View::h($expires) ?>"></label>
    <label>Certificate (PDF, up to 2 MB) <input type="file" name="certificate" accept="application/pdf,.pdf" required></label>
    <button type="submit">Upload certificate</button>
</form>

<h2>Submitted certificates</h2>
<?php if ($meterRows[0]['document_id'] === null): ?>
    <p>No certificates submitted.</p>
<?php else: ?>
    <table>
        <thead><tr><th>Type</th><th>Code</th><th>Issued</th><th>Expires</th><th>Status</th></tr></thead>
        <tbody>
        <?php foreach ($meterRows as $document): ?>
            <tr>
                <td><?= View::h($types[$document['doc_type']] ?? $document['doc_type']) ?></td>
                <td><?= View::h($document['doc_code']) ?></td>
                <td><?= View::h($document['issue_date']) ?></td>
                <td><?= View::h($document['expiry_date'] ?? '—') ?></td>
                <td><?= View::h($document['document_status']) ?></td>
            </tr>
        <?php endforeach; ?>
        </tbody>
    </table>
<?php endif; ?>
<?php View::footer(); ?>
