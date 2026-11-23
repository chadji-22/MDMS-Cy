<?php
declare(strict_types=1);

namespace Mdms;

/**
 * Slows down password guessing and mass registration: a counter per key (for example email + address) in a small file
 * under sources/var/throttle/. The file name is a hash, so no email or address is stored. If the folder cannot be
 * written the application still works and the problem is logged (availability over this extra protection).
 */
final class Throttle
{
    private static function file(string $key): ?string
    {
        $dir = dirname(__DIR__) . '/var/throttle';
        if (!is_dir($dir) && !@mkdir($dir, 0700, true) && !is_dir($dir)) {
            error_log('[MDMS] throttle folder cannot be created: ' . $dir);
            return null;
        }
        return $dir . '/' . hash('sha256', $key);
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
