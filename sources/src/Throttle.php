<?php
declare(strict_types=1);

namespace Mdms;

/**
 * Slows down password guessing and mass registration: a counter per key (for example email + address) in a small file
 * under sources/var/throttle/. The file name is a hash, so no email or address is stored. Where PHP may not write in
 * var/ (the department web server runs PHP as another user than the owner of the files) the web server's own temporary
 * folder is used instead. If neither can be written the application still works and the problem is logged
 * (availability over this extra protection).
 */
final class Throttle
{
    private static ?string $dir = null;

    private static function file(string $key): ?string
    {
        if (self::$dir === null) {
            $dir = dirname(__DIR__) . '/var/throttle';
            if (!self::writableDir($dir)) {
                // one folder per installation, so two copies of the application never share counters
                $dir = rtrim(sys_get_temp_dir(), '/\\') . '/mdms-throttle-' . substr(hash('sha256', dirname(__DIR__)), 0, 16);
                if (!self::writableDir($dir)) {
                    error_log('[MDMS] no writable throttle folder (var/throttle or the temporary folder)');
                    return null;
                }
            }
            self::$dir = $dir;
        }
        return self::$dir . '/' . hash('sha256', $key);
    }

    private static function writableDir(string $dir): bool
    {
        if (!is_dir($dir) && !@mkdir($dir, 0700, true) && !is_dir($dir)) {
            return false;
        }
        return is_writable($dir);
    }

    /** True when the key was counted at least $max times in the last $seconds. */
    public static function blocked(string $key, int $max, int $seconds): bool
    {
        return self::update($key, $seconds, false) >= $max;
    }

    public static function count(string $key, int $seconds): void
    {
        self::update($key, $seconds, true);
    }

    public static function reset(string $key): void
    {
        $file = self::file($key);
        if ($file !== null && is_file($file)) {
            @unlink($file);
        }
    }

    /** Address of the client. X-Forwarded-For is not used: anyone can send it. */
    public static function client(): string
    {
        return (string) ($_SERVER['REMOTE_ADDR'] ?? '');
    }

    private static function update(string $key, int $seconds, bool $add): int
    {
        $file = self::file($key);
        if ($file === null || (!$add && !is_file($file))) {
            return 0;
        }
        $h = @fopen($file, 'c+');
        if ($h === false) {
            error_log('[MDMS] throttle file cannot be opened');
            return 0;
        }
        flock($h, LOCK_EX);                       // two requests at once must not lose a count
        $since = time() - $seconds;
        $times = array_filter(array_map('intval', explode(',', (string) stream_get_contents($h))), static fn(int $t): bool => $t > $since);
        if ($add) {
            $times[] = time();
            ftruncate($h, 0);
            rewind($h);
            fwrite($h, implode(',', $times));
        }
        flock($h, LOCK_UN);
        fclose($h);
        return count($times);
    }
}
