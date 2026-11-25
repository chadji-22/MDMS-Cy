<?php
declare(strict_types=1);
// UC-09, second step: a technician in any approval status sends the three documents (sp_AddTechnicianDocument), sends
// a rejected one again (sp_ResubmitDocument) and applies again after a rejection (sp_ResubmitTechnician).
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, Upload, Validate, View};

Auth::requireRole('TECHNICIAN');

const FOLDER = 'technician-documents';      // the folder the officer's review page reads
const SELF = '/account/documents.php';
$types = ['ID_CARD' => 'Identity card', 'INSTALLER_LICENSE' => 'Installer licence', 'TRAINING_CERT' => 'Training certificate'];

$errors = [];
$dbError = null;
$in = ['doc_type' => '', 'doc_code' => '', 'issue_date' => '', 'expiry_date' => ''];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Upload::rejectOversized();
    Csrf::verify();
    $action = Validate::post('action');

    if ($action === 'reapply') {
        try {
            Db::callAsActor('sp_ResubmitTechnician');
            View::flash('ok', 'Your registration was sent again and is waiting for an officer.');
            header('Location: ' . View::url(SELF), true, 303);
            exit;
        } catch (DbError $e) {
            $dbError = $e;
        }
    } elseif ($action === 'add' || $action === 'resubmit') {
        $issue = Validate::date(Validate::post('issue_date'));
        $expiryRaw = Validate::post('expiry_date');
        $expiry = $expiryRaw === '' ? null : Validate::date($expiryRaw);
        if ($issue === null) {
            $errors[] = 'Enter a valid issue date.';
        } elseif ($issue > gmdate('Y-m-d')) {
            $errors[] = 'The issue date cannot be in the future.';
        }
        if ($expiryRaw !== '' && $expiry === null) {
            $errors[] = 'Enter a valid expiry date, or leave it empty.';
        } elseif ($expiry !== null && $issue !== null && $expiry < $issue) {
            $errors[] = 'The expiry date is before the issue date.';
        }
        $type = Validate::post('doc_type');
        $code = Validate::code(Validate::post('doc_code'), 60);
        $documentId = Validate::id(Validate::post('document_id'));
        if ($action === 'add') {
            foreach ($in as $name => $_) {
                $in[$name] = Validate::post($name);
            }
            if (!isset($types[$type])) { $errors[] = 'Choose a document type.'; }
            if ($code === null)        { $errors[] = 'Enter the document number (Latin letters and digits, at most 60).'; }
        } elseif ($documentId === null) {
            $errors[] = 'Choose a document of the list.';
        }
        $problem = Upload::problem('file', Upload::PDF);
        if ($problem !== null) { $errors[] = $problem; }

        if ($errors === []) {
            $path = Upload::store('file', Upload::PDF, FOLDER);
            if ($path === null) {
                $errors[] = 'The file could not be saved. Contact the application administrator.';
            } else {
                try {
                    $oldPath = null;
                    if ($action === 'add') {
                        Db::callAsActor('sp_AddTechnicianDocument', [$type, $code, $issue, $expiry, $path]);
                    } else {
                        foreach (Db::rows('sp_ListMyDocuments') as $d) {
                            if ((int) $d['document_id'] === $documentId) { $oldPath = $d['file_path']; }
                        }
                        Db::callAsActor('sp_ResubmitDocument', [$documentId, $path, $issue, $expiry]);
                    }
                } catch (DbError $e) {
                    Upload::remove($path, FOLDER);               // the database refused: keep no file
                    $dbError = $e;
                }
                if ($dbError === null) {
                    Upload::remove($oldPath, FOLDER);            // replaced by the new file
                    View::flash('ok', 'The document was uploaded and is waiting for an officer.');
                    header('Location: ' . View::url(SELF), true, 303);
                    exit;
                }
            }
        }
    } else {
        View::fail(400, 'Invalid request', 'Unknown action.');
    }
    http_response_code($dbError !== null ? $dbError->httpStatus() : 422);
}

$profile = Db::row('sp_GetMyProfile');
$status = (string) ($profile['approval_status'] ?? '');
$_SESSION['approval'] = $status;                 // an officer may have decided since the login
$documents = Db::rows('sp_ListMyDocuments');
$missing = array_diff_key($types, array_column($documents, 'doc_type', 'doc_type'));

View::header('My documents');
foreach ($errors as $message) {
    echo '<p class="flash error" role="alert">' . View::h($message) . '</p>';
}
if ($dbError !== null) {
    View::error($dbError);
}
?>
<p>Registration status: <strong><?= View::h($status) ?></strong>.
<?php if ($missing !== []): ?>
  Still missing: <?= View::h(implode(', ', $missing)) ?>.
<?php endif; ?></p>

<?php if ($status === 'REJECTED'): ?>
  <form method="post" action="<?= View::href(SELF) ?>">
    <?= Csrf::field() ?>
    <input type="hidden" name="action" value="reapply">
    <button type="submit">Apply again</button>
  </form>
<?php endif; ?>

<h2>Submitted documents</h2>
<?php if ($documents === []): ?>
  <p>No documents submitted yet.</p>
<?php else: ?>
  <div class="table-wrap"><table>
    <thead><tr><th>Type</th><th>Number</th><th>Issued</th><th>Expires</th><th>Status</th></tr></thead>
    <tbody>
    <?php foreach ($documents as $d): ?>
      <tr>
        <td><?= View::h($types[$d['doc_type']] ?? $d['doc_type']) ?></td>
        <td><?= View::h($d['doc_code']) ?></td>
        <td><?= View::h($d['issue_date']) ?></td>
        <td><?= View::h($d['expiry_date'] ?? '—') ?><?= $d['is_current'] ? '' : ' (expired)' ?></td>
        <td><?= View::h($d['approval_status']) ?></td>
      </tr>
    <?php endforeach; ?>
    </tbody>
  </table></div>
<?php endif; ?>

<?php foreach ($documents as $d): ?>
  <?php if ($d['approval_status'] === 'REJECTED'): ?>
    <h2>Send again: <?= View::h($types[$d['doc_type']] ?? $d['doc_type']) ?> <?= View::h($d['doc_code']) ?></h2>
    <form method="post" action="<?= View::href(SELF) ?>" enctype="multipart/form-data" class="card">
      <?= Csrf::field() ?>
      <input type="hidden" name="action" value="resubmit">
      <input type="hidden" name="document_id" value="<?= View::h($d['document_id']) ?>">
      <label>Issue date <input type="date" name="issue_date" value="<?= View::h($d['issue_date']) ?>" required></label>
      <label>Expiry date (optional) <input type="date" name="expiry_date" value="<?= View::h($d['expiry_date']) ?>"></label>
      <label>File (PDF, up to 2 MB) <input type="file" name="file" accept="application/pdf,.pdf" required></label>
      <button type="submit">Send again</button>
    </form>
  <?php endif; ?>
<?php endforeach; ?>

<h2>Add a document</h2>
<form method="post" action="<?= View::href(SELF) ?>" enctype="multipart/form-data" class="card">
  <?= Csrf::field() ?>
  <input type="hidden" name="action" value="add">
  <label>Type
    <select name="doc_type" required>
      <option value="">Select a type</option>
      <?php foreach ($types as $value => $label): ?>
        <option value="<?= View::h($value) ?>" <?= $in['doc_type'] === $value ? 'selected' : '' ?>><?= View::h($label) ?></option>
      <?php endforeach; ?>
    </select>
  </label>
  <label>Document number <input name="doc_code" value="<?= View::h($in['doc_code']) ?>" maxlength="60" required></label>
  <label>Issue date <input type="date" name="issue_date" value="<?= View::h($in['issue_date']) ?>" required></label>
  <label>Expiry date (optional) <input type="date" name="expiry_date" value="<?= View::h($in['expiry_date']) ?>"></label>
  <label>File (PDF, up to 2 MB) <input type="file" name="file" accept="application/pdf,.pdf" required></label>
  <button type="submit">Upload document</button>
</form>
<?php
View::footer();
