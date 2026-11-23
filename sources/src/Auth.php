<?php
declare(strict_types=1);

namespace Mdms;

/**
 * Session handling. The session is created only from a successful sp_Login. The user id in the session is the
 * ONLY source of @actor_user_id (Db::callAsActor); nothing from the request (form, query string, cookie) can set it.
 */
final class Auth
{
    public const ROLES = ['SYSTEM_ADMIN', 'SYSTEM_OFFICER', 'CONSUMER', 'TECHNICIAN', 'DSO', 'TSO', 'SUPPLIER', 'AGGREGATOR'];

    public static function startSession(): void
    {
        if (session_status() === PHP_SESSION_ACTIVE) {
            return;
        }
        $https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
            || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https');
        ini_set('session.use_strict_mode', '1');     // a session id the server did not issue is refused
        ini_set('session.use_only_cookies', '1');
        session_name('MDMSSESSID');
        session_set_cookie_params([
            'lifetime' => 0,
            'path'     => '/',
            'secure'   => $https,
            'httponly' => true,                      // not readable from JavaScript
            'samesite' => 'Lax',
        ]);
        session_start();

        // idle timeout
        $idle = max(1, (int) Config::get('SESSION_IDLE_MIN')) * 60;
        if (isset($_SESSION['last_seen']) && time() - (int) $_SESSION['last_seen'] > $idle) {
            self::destroy();
            session_start();
        }
        $_SESSION['last_seen'] = time();
    }

    /**
     * Checks the password with sp_Login and, if right, opens the session.
     * Throws DbError (category LOGIN, 50006) for a wrong password, an unknown email, an inactive or an anonymised
     * user: the database gives the same message for all of them on purpose.
     *
     * @return array<string,mixed> the user as it is kept in the session
     */
    public static function login(string $email, string $password): array
    {
        $email = trim($email);
        if ($email === '' || $password === '' || strlen($email) > 255
            || (Validate::utf16Length($password) ?? 129) > 128) {
            throw new DbError(DbError::LOGIN, 50006, 401, 'Login failed.');
        }
        // no actor yet: the user is not known until the password is right
        $row = Db::row('sp_Login', [$email, Db::nv($password, 128)], false);
        if ($row === null) {
            throw new DbError(DbError::LOGIN, 50006, 401, 'Login failed.');
        }
        session_regenerate_id(true);                 // a new id after login: no session fixation
        $_SESSION = [
            'uid'      => (int) $row['user_id'],
            'role'     => (string) $row['role_code'],
            'name'     => (string) $row['full_name'],
            'approval' => (string) ($row['approval_status'] ?? ''),
            'org'      => isset($row['organization_id']) ? (int) $row['organization_id'] : null,
            'last_seen' => time(),
        ];
        return $_SESSION;
    }

    public static function logout(): void
    {
        self::destroy();
    }

    private static function destroy(): void
    {
        $_SESSION = [];
        if (session_status() === PHP_SESSION_ACTIVE) {
            if (ini_get('session.use_cookies')) {
                $p = session_get_cookie_params();
                setcookie(session_name(), '', ['expires' => time() - 3600, 'path' => $p['path'],
                    'secure' => $p['secure'], 'httponly' => true, 'samesite' => 'Lax']);
            }
            session_destroy();
        }
    }

    public static function check(): bool
    {
        return isset($_SESSION['uid']);
    }

    /** The logged-in user's id: the actor of every protected procedure. */
    public static function userId(): int
    {
        if (!isset($_SESSION['uid'])) {
            throw new DbError(DbError::PERMISSION, 50002, 403, 'You must be logged in.');
        }
        return (int) $_SESSION['uid'];
    }

    public static function role(): string { return (string) ($_SESSION['role'] ?? ''); }
    public static function name(): string { return (string) ($_SESSION['name'] ?? ''); }
    public static function approval(): string { return (string) ($_SESSION['approval'] ?? ''); }
    public static function orgId(): ?int { return isset($_SESSION['org']) ? (int) $_SESSION['org'] : null; }

    /** Page guard: no session means the login page, then back to where the user wanted to go. */
    public static function requireLogin(): void
    {
        if (!self::check()) {
            $next = $_SERVER['REQUEST_URI'] ?? '/';
            header('Location: /login.php?next=' . rawurlencode($next), true, 303);
            exit;
        }
    }

    /** Page guard: login and one of the roles, otherwise a 403 page. */
    public static function requireRole(string ...$roles): void
    {
        self::requireLogin();
        if (!in_array(self::role(), $roles, true)) {
            View::fail(403, 'Access denied', 'Your role does not allow this page.');
        }
    }

    /** A redirect target from the request is accepted only if it is a path of this site. */
    public static function safeNext(?string $next): string
    {
        if ($next !== null && preg_match('#^/(?!/)[^\\\\\r\n]*$#', $next) === 1) {
            return $next;
        }
        return '/home.php';
    }
}
