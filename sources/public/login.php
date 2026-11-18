<?php
declare(strict_types=1);
require __DIR__ . '/../src/bootstrap.php';

use Mdms\Auth;
use Mdms\Csrf;
use Mdms\DbError;
use Mdms\View;

if (Auth::check()) {
    header('Location: /home.php', true, 303);
    exit;
}

$error = null;
$email = '';
$next = (string) ($_GET['next'] ?? $_POST['next'] ?? '');

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    $email = (string) ($_POST['email'] ?? '');
    try {
        Auth::login($email, (string) ($_POST['password'] ?? ''));
        header('Location: ' . Auth::safeNext($next), true, 303);
        exit;
    } catch (DbError $e) {
        if ($e->category() !== DbError::LOGIN) {
            throw $e;                       // a real problem (database down...) goes to the error page
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
<?php
View::footer();
