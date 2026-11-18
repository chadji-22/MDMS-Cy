<?php
declare(strict_types=1);

namespace Mdms;

/**
 * Settings. Order: environment variable, then src/config.local.php (git-ignored, for XAMPP where
 * setting environment variables is awkward), then the default below.
 * The password is never stored in the repository: put it in the environment or in config.local.php.
 */
final class Config
{
    private const DEFAULTS = [
        'DB_HOST'        => 'mssql.cs.ucy.ac.cy',
        'DB_NAME'        => '',
        'DB_USER'        => '',
        'DB_PASS'        => '',
        // The PHP login is the owner of the database. After connecting, the helper runs
        // EXECUTE AS USER = <DB_RUN_AS>: a login-less user in the role mdms_app that may EXECUTE procedures
        // but is DENIED direct SELECT / INSERT / UPDATE / DELETE (security.sql). Empty = do not switch (not recommended).
        'DB_RUN_AS'      => 'mdms_php',
        'DB_TRUST_CERT'  => '1',   // the course server uses a certificate the PHP driver does not trust by default
        'APP_DEBUG'      => '0',   // 1 only on a developer machine: exposes /health.php, shows technical detail
        'SESSION_IDLE_MIN' => '30',
    ];

    /** @var array<string,string>|null */
    private static ?array $local = null;

    public static function get(string $key): string
    {
        $env = getenv($key);
        if ($env !== false && $env !== '') {
            return $env;
        }
        if (self::$local === null) {
            $file = __DIR__ . '/config.local.php';
            self::$local = is_file($file) ? (array) require $file : [];
        }
        if (isset(self::$local[$key]) && self::$local[$key] !== '') {
            return (string) self::$local[$key];
        }
        return self::DEFAULTS[$key] ?? '';
    }

    public static function flag(string $key): bool
    {
        return in_array(strtolower(self::get($key)), ['1', 'true', 'yes', 'on'], true);
    }
}
