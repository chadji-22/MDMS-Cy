<?php
declare(strict_types=1);

namespace Mdms;

/**
 * Where the database login comes from (the Lab 7 way when no password is stored on the server).
 *
 *  - DB_PASS set in the environment or src/config.local.php: that login is used, there is no Connect page
 *    (development containers, XAMPP).
 *  - DB_PASS empty (the department web server, where any file PHP can read is readable by every account): the
 *    database name, login and password are typed once per browser session on public/connect.php and kept ONLY in the
 *    PHP session on the web server. They survive the application login and logout (to switch roles in a demo) and are
 *    forgotten on "Disconnect" and after SESSION_IDLE_MIN minutes without activity.
 */
final class Connect
{
    private const KEY = '_db';

    /** True when the password comes from the settings: no Connect page is needed. */
    public static function configured(): bool
    {
        return Config::get('DB_PASS') !== '';
    }

    public static function connected(): bool
    {
        return self::configured() || isset($_SESSION[self::KEY]['pass']);
    }

    /**
     * Database, login, password for Db::connect().
     * @return array{0:string,1:string,2:string}
     */
    public static function credentials(): array
    {
        if (self::configured()) {
            return [Config::get('DB_NAME'), Config::get('DB_USER'), Config::get('DB_PASS')];
        }
        $d = $_SESSION[self::KEY] ?? null;
        if (!is_array($d) || !isset($d['name'], $d['user'], $d['pass'])) {
            throw new DbError(DbError::SERVER, 0, 503, 'The application is not connected to the database. Open the Connect page first.');
        }
        return [(string) $d['name'], (string) $d['user'], (string) $d['pass']];
    }

    /** Called by connect.php after Db::test() accepted the login. */
    public static function remember(string $name, string $user, string $pass): void
    {
        $_SESSION[self::KEY] = ['name' => $name, 'user' => $user, 'pass' => $pass];
    }

    /** The stored login, to carry it over a session reset (Auth::login / logout). Never printed. */
    public static function snapshot(): ?array
    {
        $d = $_SESSION[self::KEY] ?? null;
        return is_array($d) ? $d : null;
    }

    public static function restore(?array $snapshot): void
    {
        if ($snapshot !== null) {
            $_SESSION[self::KEY] = $snapshot;
        }
    }

    /** Database name and login of the current connection, for display (never the password). */
    public static function label(): string
    {
        if (self::configured()) {
            return Config::get('DB_NAME') . ' (login ' . Config::get('DB_USER') . ')';
        }
        $d = self::snapshot();
        return $d === null ? '' : $d['name'] . ' (login ' . $d['user'] . ')';
    }

    /**
     * Guard of the pages that call the database before anyone is logged in (login, registration): without a
     * database login they send the visitor to the Connect page, and back here afterwards.
     */
    public static function require(): void
    {
        if (!self::connected()) {
            $back = $_SERVER['REQUEST_URI'] ?? View::url('/login.php');
            header('Location: ' . View::url('/connect.php') . '?next=' . rawurlencode($back), true, 303);
            exit;
        }
    }
}
