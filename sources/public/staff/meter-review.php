<?php
declare(strict_types=1);

require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, View};

Auth::requireRole('SYSTEM_OFFICER');

$isPost = $_SERVER['REQUEST_METHOD'] === 'POST';
if ($isPost) {
    Csrf::verify();
}

$intOptions = ['options' => ['min_range' => 1, 'max_range' => 2147483647]];
$meterId = filter_input(INPUT_GET, 'id', FILTER_VALIDATE_INT, $intOptions);
if (!$meterId) {
    View::fail(400, 'Invalid meter', 'Select a meter from Meter approvals.');
}

try {
    $rows = Db::rows('sp_GetMeter', [$meterId]);
} catch (DbError $error) {
    View::fail($error->httpStatus(), 'Meter unavailable', $error->getUserMessage());
}
if ($rows === []) {
    View::fail(404, 'Meter unavailable', 'The meter could not be found.');
}

$meter = $rows[0];
$path = View::url('/staff/meter-review.php?id=' . $meterId);   // full URL path (base included)
$types = [
    'CALIBRATION_CERT' => 'Calibration certificate',
    'CE_DECLARATION' => 'CE declaration',
    'ENCRYPTION_CERT' => 'Encryption certificate',
];
$documents = [];
$approved = [];
foreach ($rows as $row) {
    if ($row['document_id'] !== null && isset($types[$row['doc_type']])) {
        $documents[$row['document_id']] = $row;
        if ($row['document_status'] === 'APPROVED') {
            $approved[$row['doc_type']] = true;
        }
    }
}
$canActivate = count($approved) === count($types);

if (!$isPost && filter_has_var(INPUT_GET, 'download')) {
    $documentId = filter_input(INPUT_GET, 'download', FILTER_VALIDATE_INT, $intOptions);
    $filePath = $documents[$documentId]['file_path'] ?? '';
    if (preg_match('/\Ameter-certificates\/[a-f0-9]{32}\.pdf\z/', $filePath) !== 1) {
        View::fail(404, 'File unavailable', 'The certificate PDF is unavailable.');
    }
    $file = __DIR__ . '/../../var/' . $filePath;
    if (!is_file($file) || !is_readable($file)) {
        View::fail(404, 'File unavailable', 'The certificate PDF is unavailable.');
    }
    header('Content-Type: application/pdf');
    header('Content-Disposition: attachment; filename="certificate-' . $documentId . '.pdf"');
    header('X-Content-Type-Options: nosniff');
    header('Cache-Control: no-store');
    readfile($file);
    exit;
}

$reviewError = null;
if ($isPost) {
    $action = filter_input(INPUT_POST, 'action');
    $decision = filter_input(INPUT_POST, 'decision');
    $comment = trim((string) filter_input(INPUT_POST, 'comment'));
    if (!in_array($decision, ['approve', 'reject'], true) || preg_match('/\A.{0,500}\z/su', $comment) !== 1) {
        View::fail(400, 'Invalid decision', 'Choose a decision and use at most 500 characters for the comment.');
    }
    $note = Db::nv($comment === '' ? null : $comment, 500);

    try {
        if ($action === 'document') {
            $documentId = filter_input(INPUT_POST, 'document_id', FILTER_VALIDATE_INT, $intOptions);
            if (($documents[$documentId]['document_status'] ?? null) !== 'PENDING') {
                View::fail(409, 'Certificate unavailable', 'Select a pending certificate for this meter.');
            }
            Db::callAsActor('sp_DecideDocument', [$documentId, $decision === 'approve' ? 'APPROVED' : 'REJECTED', $note]);
            View::flash('ok', $decision === 'approve' ? 'Certificate approved.' : 'Certificate rejected.');
        } elseif ($action === 'meter') {
            if ($meter['status'] !== 'PENDING' || ($decision === 'approve' && !$canActivate)) {
                View::fail(409, 'Meter decision unavailable', 'Activation requires a pending meter and all three approved certificates.');
            }
            Db::callAsActor('sp_ConfirmMeter', [$meterId, strtoupper($decision), $note]);
            View::flash('ok', $decision === 'approve' ? 'Meter activated.' : 'Meter installation rejected.');
        } else {
            View::fail(400, 'Invalid action', 'Reload the meter review and try again.');
        }
        header('Location: ' . $path, true, 303);
        exit;
    } catch (DbError $error) {
        $reviewError = $error;
    }
}

View::header('Review meter #' . $meterId);
?>
<p><a href="<?= View::base() ?>/staff/meters.php">Back to Meter approvals</a></p>
<dl>
    <dt>Serial number</dt><dd><?= View::h($meter['serial_number']) ?></dd>
    <dt>Premise</dt><dd><?= View::h($meter['premise_address']) ?></dd>
    <dt>Status</dt><dd><?= View::h($meter['status']) ?></dd>
</dl>
<?php if ($reviewError !== null): ?>
    <?php View::error($reviewError); ?>
<?php endif; ?>
<h2>Certificates</h2>
<?php if ($documents === []): ?>
    <p>No certificates submitted.</p>
<?php else: ?>
    <table>
        <thead><tr><th>Type</th><th>Code</th><th>Dates</th><th>Status</th><th>Decision</th></tr></thead>
        <tbody>
        <?php foreach ($documents as $documentId => $document): ?>
            <tr>
                <td><?= View::h($types[$document['doc_type']]) ?></td>
                <td><?= View::h($document['doc_code']) ?>
                    <?php if (preg_match('/\Ameter-certificates\/[a-f0-9]{32}\.pdf\z/', $document['file_path'] ?? '') === 1): ?>
                        <br><a href="<?= View::h($path . '&download=' . $documentId) ?>">Download PDF</a>
                    <?php endif; ?>
                </td>
                <td>Issued <?= View::h($document['issue_date']) ?><?php if ($document['expiry_date'] !== null): ?>
                    <br>Expires <?= View::h($document['expiry_date']) ?><?php endif; ?>
                </td>
                <td><?= View::h($document['document_status']) ?></td>
                <td>
                    <?php if ($document['document_status'] === 'PENDING'): ?>
                        <form method="post" action="<?= View::h($path) ?>">
                            <?= Csrf::field() ?>
                            <input type="hidden" name="action" value="document">
                            <input type="hidden" name="document_id" value="<?= View::h($documentId) ?>">
                            <label>Comment <input name="comment" maxlength="500"></label>
                            <button name="decision" value="approve">Approve</button>
                            <button name="decision" value="reject">Reject</button>
                        </form>
                    <?php endif; ?>
                </td>
            </tr>
        <?php endforeach; ?>
        </tbody>
    </table>
<?php endif; ?>
<?php if ($meter['status'] === 'PENDING'): ?>
    <h2>Installation decision</h2>
    <?php if (!$canActivate): ?>
        <p>Approve all three required certificate types to activate this meter.</p>
    <?php endif; ?>
    <form method="post" action="<?= View::h($path) ?>" class="card">
        <?= Csrf::field() ?>
        <input type="hidden" name="action" value="meter">
        <label>Comment <input name="comment" maxlength="500"></label>
        <button name="decision" value="approve" <?= $canActivate ? '' : 'disabled' ?>>Activate meter</button>
        <button name="decision" value="reject">Reject installation</button>
    </form>
<?php endif; ?>
<?php View::footer(); ?>
