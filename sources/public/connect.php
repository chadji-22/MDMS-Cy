<?php
declare(strict_types=1);
/**
 * Connect page (the Lab 7 way): the database name, login and password are typed once per browser session and kept
 * only in the PHP session on the web server, never in a file. Used when DB_PASS is not set in the settings, e.g. on
 * students.cs.ucy.ac.cy, where every file PHP can read is also readable by every other account. Same field names
 * as the Lab 7 connect.php: dbName, userName, pswd.
 */
require __DIR__ . '/../src/bootstrap.php';

use Mdms\{Auth, Config, Connect, Csrf, Db, DbError, Throttle, View};

$next = $_GET['next'] ?? $_POST['next'] ?? '';
$next = is_string($next) && $next !== '' ? $next : View::url('/login.php');
$target = Auth::safeNext($next);                     // only a path of this application

if (Connect::configured()) {                         // the password is in the settings: nothing to type here
    header('Location: ' . $target, true, 303);
    exit;
}

$error = null;
$dbName = Config::get('DB_NAME');
$userName = Config::get('DB_USER');

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    if (($_POST['action'] ?? '') === 'disconnect') {
        Auth::logout(false);                         // forget the application login AND the database login
        header('Location: ' . View::url('/connect.php'), true, 303);
        exit;
    }
    $dbName = is_string($_POST['dbName'] ?? null) ? trim($_POST['dbName']) : '';
    $userName = is_string($_POST['userName'] ?? null) ? trim($_POST['userName']) : '';
    $pswd = is_string($_POST['pswd'] ?? null) ? $_POST['pswd'] : '';

    // Wrong passwords could make the SQL Server lock the login: 5 tries per 15 minutes, counted per address (file, if
    // var/ is writable) and per browser session (always works, also where var/ is read-only).
    $key = 'connect|' . Throttle::client();
    $recent = array_filter((array) ($_SESSION['connect_fail'] ?? []), static fn($t): bool => is_int($t) && $t > time() - 900);
    if (Throttle::blocked($key, 5, 900) || count($recent) >= 5) {
        header('Retry-After: 900');
        View::fail(429, 'Too many attempts', 'Too many failed connection attempts. Wait 15 minutes and try again.');
    }

    if ($dbName === '' || $userName === '' || $pswd === '') {
        $message = 'All three fields are required.';
    } elseif (strlen($dbName) > 128 || strlen($userName) > 128 || strlen($pswd) > 128
        || preg_match('/[\x00-\x1F]/', $dbName . $userName) === 1) {
        $message = 'A field is too long or contains invalid characters.';
    } else {
        $message = Db::test($dbName, $userName, $pswd);
    }

    if ($message === null) {
        session_regenerate_id(true);                 // a new session id now that it holds a password
        unset($_SESSION['connect_fail']);
        Connect::remember($dbName, $userName, $pswd);
        Throttle::reset($key);
        header('Location: ' . $target, true, 303);
        exit;
    }
    if ($pswd !== '') {                               // a refused password counts, an empty form does not
        Throttle::count($key, 900);
        $recent[] = time();
        $_SESSION['connect_fail'] = array_values($recent);
    }
    $error = new DbError(DbError::LOGIN, 0, 401, $message);
    http_response_code(401);
}

View::header('Connect to the database');
if ($error !== null) {
    View::error($error);
}
if (Connect::connected()): ?>
<p>Connected to <strong><?= View::h(Connect::label()) ?></strong> on <span class="mono"><?= View::h(Config::get('DB_HOST')) ?></span>.</p>
<p><a href="<?= View::h($target) ?>">Continue</a></p>
<form method="post" action="<?= View::base() ?>/connect.php" class="inline">
  <?= Csrf::field() ?>
  <button type="submit" name="action" value="disconnect">Disconnect</button>
</form>
<?php else: ?>
<form method="post" action="<?= View::base() ?>/connect.php" class="card" autocomplete="off">
  <?= Csrf::field() ?>
  <input type="hidden" name="next" value="<?= View::h($next) ?>">
  <p class="muted">Server: <span class="mono"><?= View::h(Config::get('DB_HOST')) ?></span></p>
  <label>Database <input type="text" name="dbName" value="<?= View::h($dbName) ?>" maxlength="128" required></label>
  <label>Login <input type="text" name="userName" value="<?= View::h($userName) ?>" maxlength="128" required></label>
  <label>Password <input type="password" name="pswd" maxlength="128" required autofocus></label>
  <button type="submit" name="connect" value="1">Connect</button>
</form>
<p class="muted small">The password is kept only in this browser session on the web server, never in a file. Logging out of
  the application keeps the connection (to log in as another user); <em>Disconnect</em> forgets it, and so do
  <?= (int) Config::get('SESSION_IDLE_MIN') ?> minutes without activity.</p>
<?php endif;
View::footer();
