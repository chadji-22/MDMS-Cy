<?php
declare(strict_types=1);
// UC-09, first step: a technician registers and stays PENDING (sp_RegisterTechnician). The three documents follow in
// /account/documents.php; an officer decides.
require __DIR__ . '/../src/bootstrap.php';

use Mdms\{Auth, Connect, Csrf, Db, DbError, Throttle, Upload, Validate, View};

if (Auth::check()) {
    header('Location: ' . View::url('/home.php'), true, 303);
    exit;
}
Connect::require();                         // no database login yet (department server): the Connect page first

$in = ['email' => '', 'full_name' => '', 'phone' => '', 'birth_date' => '', 'specialty' => ''];
$errors = [];
$dbError = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Upload::rejectOversized();
    Csrf::verify();
    foreach ($in as $name => $_) {
        $in[$name] = Validate::post($name);
    }
    $password = Validate::post('password');

    $email = Validate::email($in['email']);
    $fullName = Validate::text($in['full_name'], 150);
    $phone = Validate::phone($in['phone']);
    $birth = Validate::date($in['birth_date']);
    $specialty = Validate::text($in['specialty'], 100);
    if ($email === null)     { $errors[] = 'Enter a valid email address.'; }
    if ($fullName === null)  { $errors[] = 'Enter your full name (at most 150 characters).'; }
    if ($phone === null)     { $errors[] = 'Enter a valid phone number.'; }
    if ($birth === null || $birth < '1900-01-01') { $errors[] = 'Enter a valid birth date.'; }
    if ($specialty === null) { $errors[] = 'Enter your specialty (at most 100 characters).'; }
    $problem = Validate::passwordProblem($password, Validate::post('password2'));
    if ($problem !== null)   { $errors[] = $problem; }
    $problem = Upload::problem('photo', Upload::IMAGE);
    if ($problem !== null)   { $errors[] = 'Photo: ' . $problem; }

    // B10: at most 30 registrations per hour from one address
    if ($errors === [] && Throttle::blocked('register|' . Throttle::client(), 30, 3600)) {
        View::fail(429, 'Too many registrations', 'Too many registrations from this address. Try again later.');
    }
    if ($errors === []) {
        Throttle::count('register|' . Throttle::client(), 3600);
        $photo = Upload::store('photo', Upload::IMAGE, 'technician-photos');
        if ($photo === null) {
            $errors[] = 'The photo could not be saved. Contact the application administrator.';
            http_response_code(500);
        } else {
            try {
                Db::call('sp_RegisterTechnician', [
                    $email, Db::nv($password, 128), Db::nv($fullName, 150), $phone, $birth, $photo, Db::nv($specialty, 100),
                ]);
                View::flash('ok', 'Your registration was received. Log in and upload your three documents, so that an officer can approve you.');
                header('Location: ' . View::url('/login.php') . '?next=' . rawurlencode(View::url('/account/documents.php')), true, 303);
                exit;
            } catch (DbError $e) {
                Upload::remove($photo, 'technician-photos');     // no account, so no file either
                $dbError = $e;
                http_response_code($e->httpStatus());
            }
        }
    } else {
        http_response_code(422);
    }
}

View::header('Register as a technician');
foreach ($errors as $message) {
    echo '<p class="flash error" role="alert">' . View::h($message) . '</p>';
}
if ($dbError !== null) {
    View::error($dbError);
}
?>
<p>An officer checks every registration. You cannot take jobs before it is approved.</p>
<form method="post" action="<?= View::base() ?>/register-technician.php" enctype="multipart/form-data" class="card">
  <?= Csrf::field() ?>
  <label>Full name <input name="full_name" value="<?= View::h($in['full_name']) ?>" maxlength="150" autocomplete="name" required></label>
  <label>Email <input type="email" name="email" value="<?= View::h($in['email']) ?>" maxlength="255" autocomplete="email" required></label>
  <label>Phone <input type="tel" name="phone" value="<?= View::h($in['phone']) ?>" maxlength="20" autocomplete="tel" required></label>
  <label>Birth date (18 or older) <input type="date" name="birth_date" value="<?= View::h($in['birth_date']) ?>" required></label>
  <label>Specialty <input name="specialty" list="specialties" value="<?= View::h($in['specialty']) ?>" maxlength="100" required></label>
  <datalist id="specialties"><option value="Ηλεκτρολόγος Α΄"><option value="Τηλεπικοινωνίες"></datalist>
  <label>Photo (JPG or PNG, up to 2 MB) <input type="file" name="photo" accept="image/jpeg,image/png" required></label>
  <label>Password (at least 8 characters) <input type="password" name="password" maxlength="128" minlength="8" autocomplete="new-password" required></label>
  <label>Repeat the password <input type="password" name="password2" maxlength="128" autocomplete="new-password" required></label>
  <button type="submit">Register</button>
</form>
<p><a href="<?= View::base() ?>/login.php">Back to the login page</a></p>
<?php
View::footer();
