<?php
declare(strict_types=1);
// Every role: change of the own password (sp_ChangePassword checks the old one).
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, Validate, View};

Auth::requireLogin();

$error = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    $old = Validate::post('old_password');
    $new = Validate::post('password');

    $error = Validate::passwordProblem($new, Validate::post('password2'));
    if ($error === null && $old === $new) {
        $error = 'The new password must be different from the current one.';
    }
    if ($error !== null) {
        http_response_code(422);
    } elseif ((Validate::utf16Length($old) ?? 129) > 128) {
        $error = 'The current password is not correct.';
        http_response_code(422);
    } else {
        try {
            Db::callAsActor('sp_ChangePassword', [Db::nv($old, 128), Db::nv($new, 128)]);
            session_regenerate_id(true);
            unset($_SESSION['csrf']);                       // forms opened before the change are no longer valid
            View::flash('ok', 'Your password was changed.');
            header('Location: /account/profile.php', true, 303);
            exit;
        } catch (DbError $e) {
            $error = $e->category() === DbError::LOGIN ? 'The current password is not correct.' : $e->getUserMessage();
            http_response_code($e->category() === DbError::LOGIN ? 422 : $e->httpStatus());
        }
    }
}

View::header('Change my password');
if ($error !== null) {
    echo '<p class="flash error" role="alert">' . View::h($error) . '</p>';
}
?>
<form method="post" action="/account/password.php" class="card">
  <?= Csrf::field() ?>
  <label>Current password <input type="password" name="old_password" maxlength="128" autocomplete="current-password" required></label>
  <label>New password (at least 8 characters) <input type="password" name="password" maxlength="128" minlength="8" autocomplete="new-password" required></label>
  <label>Repeat the new password <input type="password" name="password2" maxlength="128" autocomplete="new-password" required></label>
  <button type="submit">Change password</button>
</form>
<p><a href="/account/profile.php">Back to my profile</a></p>
<?php
View::footer();
