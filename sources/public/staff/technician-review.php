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
$technicianId = filter_input(INPUT_GET, 'id', FILTER_VALIDATE_INT, $intOptions);
if (!$technicianId) {
    View::fail(400, 'Invalid technician', 'Select a technician from Technician approvals.');
}

try {
    $rows = Db::rows('sp_GetTechnicianReview', [$technicianId]);
} catch (DbError $error) {
    View::fail($error->httpStatus(), 'Technician unavailable', $error->getUserMessage());
}
if ($rows === []) {
    View::fail(404, 'Technician unavailable', 'The technician could not be found.');
}

$technician = $rows[0];
$path = '/staff/technician-review.php?id=' . $technicianId;
$types = ['ID_CARD' => 'Identity card', 'INSTALLER_LICENSE' => 'Installer licence', 'TRAINING_CERT' => 'Training certificate'];
$documents = [];
$approved = [];
foreach ($rows as $row) {
    if ($row['document_id'] !== null && isset($types[$row['doc_type']])) {
        $documents[$row['document_id']] = $row;
        if ($row['document_status'] === 'APPROVED' && $row['is_current']) {
            $approved[$row['doc_type']] = true;
        }
    }
}
$canApprove = count($approved) === count($types);
$status = $technician['approval_status'];
$accountDecisions = match ($status) {
    'PENDING' => ['APPROVED' => 'Approve technician', 'REJECTED' => 'Reject technician'],
    'APPROVED' => ['SUSPENDED' => 'Suspend technician'],
    'SUSPENDED' => ['APPROVED' => 'Reinstate technician'],
    default => [],
};
$documentPathPattern = '/\Atechnician-documents\/[a-f0-9]{32}\.pdf\z/';

if (!$isPost && filter_has_var(INPUT_GET, 'download')) {
    $documentId = filter_input(INPUT_GET, 'download', FILTER_VALIDATE_INT, $intOptions);
    $filePath = $documents[$documentId]['file_path'] ?? '';
    $file = __DIR__ . '/../../var/' . $filePath;
    if (preg_match($documentPathPattern, $filePath) !== 1 || !is_file($file) || !is_readable($file)) {
        View::fail(404, 'File unavailable', 'The document PDF is unavailable.');
    }
    header('Content-Type: application/pdf');
    header('Content-Disposition: attachment; filename="technician-document-' . $documentId . '.pdf"');
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
    if (preg_match('/\A.{0,500}\z/su', $comment) !== 1) {
        View::fail(400, 'Invalid comment', 'Use at most 500 characters for the comment.');
    }
    $note = Db::nv($comment === '' ? null : $comment, 500);

    try {
        if ($action === 'document') {
            $documentId = filter_input(INPUT_POST, 'document_id', FILTER_VALIDATE_INT, $intOptions);
            if (!in_array($decision, ['APPROVED', 'REJECTED'], true)) {
                View::fail(400, 'Invalid decision', 'Choose Approve or Reject.');
            }
            if (($documents[$documentId]['document_status'] ?? null) !== 'PENDING') {
                View::fail(409, 'Document unavailable', 'Select a pending document for this technician.');
            }
            Db::callAsActor('sp_DecideDocument', [$documentId, $decision, $note]);
            View::flash('ok', $decision === 'APPROVED' ? 'Document approved.' : 'Document rejected.');
        } elseif ($action === 'technician') {
            if (!isset($accountDecisions[$decision]) || ($decision === 'APPROVED' && !$canApprove)) {
                View::fail(409, 'Decision unavailable', 'Approval requires all three documents to be approved and unexpired.');
            }
            Db::callAsActor('sp_DecideTechnician', [$technicianId, $decision, $note]);
            View::flash('ok', 'Technician status updated to ' . $decision . '.');
        } else {
            View::fail(400, 'Invalid action', 'Reload the technician review and try again.');
        }
        header('Location: ' . $path, true, 303);
        exit;
    } catch (DbError $error) {
        $reviewError = $error;
    }
}

View::header('Review technician #' . $technicianId);
?>
<p><a href="/staff/technicians.php">Back to Technician approvals</a></p>
<dl>
    <dt>Name</dt><dd><?= View::h($technician['full_name']) ?></dd>
    <dt>Email</dt><dd><?= View::h($technician['email']) ?></dd>
    <dt>Specialty</dt><dd><?= View::h($technician['specialty']) ?></dd>
    <dt>Status</dt><dd><?= View::h($status) ?></dd>
</dl>
<?php if ($reviewError !== null): ?>
    <?php View::error($reviewError); ?>
<?php endif; ?>
<h2>Documents</h2>
<?php if ($documents === []): ?>
    <p>No documents submitted.</p>
<?php else: ?>
    <table>
        <thead><tr><th>Type</th><th>Code</th><th>Dates</th><th>Status</th><th>Decision</th></tr></thead>
        <tbody>
        <?php foreach ($documents as $documentId => $document): ?>
            <tr>
                <td><?= View::h($types[$document['doc_type']]) ?></td>
                <td><?= View::h($document['doc_code']) ?>
                    <?php if (preg_match($documentPathPattern, $document['file_path'] ?? '') === 1): ?>
                        <br><a href="<?= View::h($path . '&download=' . $documentId) ?>">Download PDF</a>
                    <?php endif; ?>
                </td>
                <td>Issued <?= View::h($document['issue_date']) ?><?php if ($document['expiry_date'] !== null): ?>
                    <br>Expires <?= View::h($document['expiry_date']) ?><?php endif; ?>
                </td>
                <td><?= View::h($document['document_status']) ?><?php if (!$document['is_current']): ?><br>Expired<?php endif; ?></td>
                <td>
                    <?php if ($document['document_status'] === 'PENDING'): ?>
                        <form method="post" action="<?= View::h($path) ?>">
                            <?= Csrf::field() ?>
                            <input type="hidden" name="action" value="document">
                            <input type="hidden" name="document_id" value="<?= View::h($documentId) ?>">
                            <label>Comment <input name="comment" maxlength="500"></label>
                            <button name="decision" value="APPROVED">Approve</button>
                            <button name="decision" value="REJECTED">Reject</button>
                        </form>
                    <?php endif; ?>
                </td>
            </tr>
        <?php endforeach; ?>
        </tbody>
    </table>
<?php endif; ?>

<?php if ($accountDecisions !== []): ?>
    <h2>Technician decision</h2>
    <?php if (isset($accountDecisions['APPROVED']) && !$canApprove): ?>
        <p>Approve a current identity card, installer licence and training certificate first.</p>
    <?php endif; ?>
    <form method="post" action="<?= View::h($path) ?>" class="card">
        <?= Csrf::field() ?>
        <input type="hidden" name="action" value="technician">
        <label>Comment <input name="comment" maxlength="500"></label>
        <?php foreach ($accountDecisions as $decision => $label): ?>
            <button name="decision" value="<?= View::h($decision) ?>" <?= $decision === 'APPROVED' && !$canApprove ? 'disabled' : '' ?>><?= View::h($label) ?></button>
        <?php endforeach; ?>
    </form>
<?php endif; ?>
<?php View::footer(); ?>
