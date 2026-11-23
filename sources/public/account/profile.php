<?php
declare(strict_types=1);
// Every role: own details (sp_GetMyProfile) and their change (sp_UpdateMyProfile).
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, Validate, View};

Auth::requireLogin();

$isPost = $_SERVER['REQUEST_METHOD'] === 'POST';
if ($isPost) {
    Csrf::verify();
}

$profile = Db::row('sp_GetMyProfile');
if ($profile === null) {
    View::fail(404, 'Profile unavailable', 'Your profile could not be found.');
}
// sp_UpdateMyProfile overwrites the phone: never show the form when the current one was not read.
if (!array_key_exists('phone', $profile)) {
    View::fail(500, 'Service problem', 'The database is older than this page (view_ORGANIZATION_USER has no phone). Run views.sql.');
}

$isConsumer = Auth::role() === 'CONSUMER';
$isTechnician = Auth::role() === 'TECHNICIAN';
if ($isTechnician) {
    $_SESSION['approval'] = (string) $profile['approval_status'];   // an officer may have decided since the login
}

$in = [
    'full_name' => (string) $profile['full_name'],
    'phone'     => (string) ($profile['phone'] ?? ''),
    'iban'      => (string) ($profile['iban'] ?? ''),
];
$notifyEmail = (bool) ($profile['notify_email'] ?? false);
$notifySms = (bool) ($profile['notify_sms'] ?? false);
$errors = [];
$dbError = null;

if ($isPost) {
    $in['full_name'] = Validate::post('full_name');
    $in['phone'] = Validate::post('phone');
    $in['iban'] = Validate::post('iban');
    $notifyEmail = isset($_POST['notify_email']);
    $notifySms = isset($_POST['notify_sms']);

    $fullName = Validate::text($in['full_name'], 150);
    $phone = Validate::phone($in['phone']);
    $iban = null;
    if ($fullName === null) { $errors[] = 'Enter your full name (at most 150 characters).'; }
    if ($phone === null && trim($in['phone']) !== '') { $errors[] = 'Enter a valid phone number, or leave it empty.'; }
    if ($isConsumer) {
        $iban = Validate::iban($in['iban']);
        if ($iban === null) { $errors[] = 'Enter a valid IBAN.'; }
    }

    if ($errors === []) {
        try {
            Db::callAsActor('sp_UpdateMyProfile', [
                Db::nv($fullName, 150), $phone, $iban,
                $isConsumer ? (int) $notifyEmail : null, $isConsumer ? (int) $notifySms : null,
            ]);
            $_SESSION['name'] = $fullName;                 // shown in the page header
            View::flash('ok', 'Your profile was saved.');
            header('Location: /account/profile.php', true, 303);
            exit;
        } catch (DbError $e) {
            $dbError = $e;
            http_response_code($e->httpStatus());
        }
    } else {
        http_response_code(422);
    }
}

View::header('My profile');
foreach ($errors as $message) {
    echo '<p class="flash error" role="alert">' . View::h($message) . '</p>';
}
if ($dbError !== null) {
    View::error($dbError);
}
?>
<table>
  <tbody>
    <tr><th scope="row">Email</th><td><?= View::h($profile['email']) ?></td></tr>
    <tr><th scope="row">Role</th><td><?= View::h(Auth::role()) ?></td></tr>
    <?php if (isset($profile['organization_name'])): ?>
      <tr><th scope="row">Organization</th><td><?= View::h($profile['organization_name']) ?></td></tr>
    <?php endif; ?>
    <?php if ($isConsumer): ?>
      <tr><th scope="row">Member since</th><td><?= View::h(substr((string) $profile['created_at'], 0, 10)) ?></td></tr>
    <?php endif; ?>
    <?php if ($isTechnician): ?>
      <tr><th scope="row">Approval</th><td><?= View::h($profile['approval_status']) ?> · <a href="/account/documents.php">My documents</a></td></tr>
      <tr><th scope="row">Specialty</th><td><?= View::h($profile['specialty']) ?></td></tr>
      <tr><th scope="row">Birth date</th><td><?= View::h($profile['birth_date']) ?></td></tr>
      <tr><th scope="row">Photo</th><td><a href="/account/photo.php">Show my photo</a></td></tr>
    <?php endif; ?>
  </tbody>
</table>

<h2>Change my details</h2>
<form method="post" action="/account/profile.php" class="card">
  <?= Csrf::field() ?>
  <label>Full name <input name="full_name" value="<?= View::h($in['full_name']) ?>" maxlength="150" autocomplete="name" required></label>
  <label>Phone <input type="tel" name="phone" value="<?= View::h($in['phone']) ?>" maxlength="20" autocomplete="tel"></label>
  <?php if ($isConsumer): ?>
    <label>IBAN <input name="iban" value="<?= View::h($in['iban']) ?>" maxlength="42" required></label>
    <label class="check"><input type="checkbox" name="notify_email" value="1" <?= $notifyEmail ? 'checked' : '' ?>> Notify me by email</label>
    <label class="check"><input type="checkbox" name="notify_sms" value="1" <?= $notifySms ? 'checked' : '' ?>> Notify me by SMS</label>
  <?php endif; ?>
  <button type="submit">Save</button>
</form>
<p><a href="/account/password.php">Change my password</a></p>
<?php
View::footer();
