<?php
declare(strict_types=1);
require __DIR__ . '/../src/bootstrap.php';

use Mdms\Auth;
use Mdms\Csrf;
use Mdms\DbError;
use Mdms\Throttle;
use Mdms\View;

if (Auth::check()) {
    header('Location: /home.php', true, 303);
    exit;
}

$error = null;
$email = '';
$next = $_GET['next'] ?? $_POST['next'] ?? '';
$next = is_string($next) ? $next : '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    $email = is_string($_POST['email'] ?? null) ? $_POST['email'] : '';
    // B10: 5 wrong passwords for one email, or 50 from one address, in 15 minutes -> wait. Counted before the database
    // is asked and the same for a known and an unknown email, so it tells nobody which accounts exist.
    $keys = ['login|' . strtolower(trim($email)) . '|' . Throttle::client() => 5, 'login-ip|' . Throttle::client() => 50];
    foreach ($keys as $key => $max) {
        if (Throttle::blocked($key, $max, 900)) {
            header('Retry-After: 900');
            View::fail(429, 'Too many attempts', 'Too many failed logins. Wait 15 minutes and try again.');
        }
    }
    try {
        Auth::login($email, is_string($_POST['password'] ?? null) ? $_POST['password'] : '');
        Throttle::reset(array_key_first($keys));
        header('Location: ' . Auth::safeNext($next), true, 303);
        exit;
    } catch (DbError $e) {
        if ($e->category() !== DbError::LOGIN) {
            throw $e;                       // a real problem (database down...) goes to the error page
        }
        foreach ($keys as $key => $_) {
            Throttle::count($key, 900);
        }
        $error = $e;                        // wrong password / unknown email / inactive user: one and the same message
        http_response_code(401);
    }
}

View::header('Log in');
if ($error !== null) {
    View::error($error);
}
?>
<form method="post" action="/login.php" class="card" autocomplete="on">
  <?= Csrf::field() ?>
  <input type="hidden" name="next" value="<?= View::h($next) ?>">
  <label>Email <input type="email" name="email" value="<?= View::h($email) ?>" maxlength="255" required autofocus></label>
  <label>Password <input type="password" name="password" maxlength="128" required></label>
  <button type="submit">Log in</button>
</form>
<p>New here? <a href="/register.php">Create a consumer account</a> or <a href="/register-technician.php">register as a technician</a>.</p>
<?php
View::footer();
