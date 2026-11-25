<?php
declare(strict_types=1);
// UC-01: a consumer creates an account, no approval needed (sp_RegisterConsumer).
require __DIR__ . '/../src/bootstrap.php';

use Mdms\{Auth, Connect, Csrf, Db, DbError, Throttle, Validate, View};

if (Auth::check()) {
    header('Location: ' . View::url('/home.php'), true, 303);
    exit;
}
Connect::require();                         // no database login yet (department server): the Connect page first

$in = ['email' => '', 'full_name' => '', 'phone' => '', 'iban' => ''];
$notifyEmail = true;
$notifySms = false;
$errors = [];
$dbError = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    foreach ($in as $name => $_) {
        $in[$name] = Validate::post($name);
    }
    $notifyEmail = isset($_POST['notify_email']);
    $notifySms = isset($_POST['notify_sms']);
    $password = Validate::post('password');

    $email = Validate::email($in['email']);
    $fullName = Validate::text($in['full_name'], 150);
    $phone = Validate::phone($in['phone']);
    $iban = Validate::iban($in['iban']);
    if ($email === null)    { $errors[] = 'Enter a valid email address.'; }
    if ($fullName === null) { $errors[] = 'Enter your full name (at most 150 characters).'; }
    if ($phone === null)    { $errors[] = 'Enter a valid phone number.'; }
    if ($iban === null)     { $errors[] = 'Enter a valid IBAN.'; }
    $problem = Validate::passwordProblem($password, Validate::post('password2'));
    if ($problem !== null)  { $errors[] = $problem; }

    // B10: at most 30 registrations per hour from one address
    if ($errors === [] && Throttle::blocked('register|' . Throttle::client(), 30, 3600)) {
        View::fail(429, 'Too many registrations', 'Too many registrations from this address. Try again later.');
    }
    if ($errors === []) {
        Throttle::count('register|' . Throttle::client(), 3600);
        try {
            Db::call('sp_RegisterConsumer', [
                $email, Db::nv($password, 128), Db::nv($fullName, 150), $phone, $iban,
                $notifyEmail ? 1 : 0, $notifySms ? 1 : 0,
            ]);
            View::flash('ok', 'Your account was created. You can log in now.');
            header('Location: ' . View::url('/login.php'), true, 303);
            exit;
        } catch (DbError $e) {
            $dbError = $e;
            http_response_code($e->httpStatus());
        }
    } else {
        http_response_code(422);
    }
}

View::header('Create a consumer account');
foreach ($errors as $message) {
    echo '<p class="flash error" role="alert">' . View::h($message) . '</p>';
}
if ($dbError !== null) {
    View::error($dbError);
}
?>
<form method="post" action="<?= View::base() ?>/register.php" class="card">
  <?= Csrf::field() ?>
  <label>Full name <input name="full_name" value="<?= View::h($in['full_name']) ?>" maxlength="150" autocomplete="name" required></label>
  <label>Email <input type="email" name="email" value="<?= View::h($in['email']) ?>" maxlength="255" autocomplete="email" required></label>
  <label>Phone <input type="tel" name="phone" value="<?= View::h($in['phone']) ?>" maxlength="20" autocomplete="tel" required></label>
  <label>IBAN <input name="iban" value="<?= View::h($in['iban']) ?>" maxlength="42" required></label>
  <label>Password (at least 8 characters) <input type="password" name="password" maxlength="128" minlength="8" autocomplete="new-password" required></label>
  <label>Repeat the password <input type="password" name="password2" maxlength="128" autocomplete="new-password" required></label>
  <label class="check"><input type="checkbox" name="notify_email" value="1" <?= $notifyEmail ? 'checked' : '' ?>> Notify me by email</label>
  <label class="check"><input type="checkbox" name="notify_sms" value="1" <?= $notifySms ? 'checked' : '' ?>> Notify me by SMS</label>
  <button type="submit">Create account</button>
</form>
<p><a href="<?= View::base() ?>/login.php">Back to the login page</a></p>
<?php
View::footer();
