<?php
declare(strict_types=1);

namespace Mdms;

/**
 * Checks on what the browser sends. They give the user a clear message before the database is called; the procedures
 * and the CHECK constraints stay the real rule. Every function returns the clean value, or null when it is not valid.
 */
final class Validate
{
    /** A field of the form as a string. A crafted array (name[]=x) counts as empty. */
    public static function post(string $name): string
    {
        $v = $_POST[$name] ?? '';
        return is_string($v) ? $v : '';
    }

    /** Required one-line text: valid UTF-8, trimmed, no control characters, 1..$max characters. */
    public static function text(string $value, int $max): ?string
    {
        $value = trim($value);
        return preg_match('/\A[^\p{C}]{1,' . $max . '}\z/u', $value) === 1 ? $value : null;
    }

    /** Printable ASCII for the VARCHAR code columns. */
    public static function code(string $value, int $max): ?string
    {
        $value = trim($value);
        return preg_match('/\A[ -~]{1,' . $max . '}\z/', $value) === 1 ? $value : null;
    }

    public static function email(string $value): ?string
    {
        $value = trim($value);
        return strlen($value) <= 255 && filter_var($value, FILTER_VALIDATE_EMAIL) !== false ? $value : null;
    }

    public static function phone(string $value): ?string
    {
        $value = trim($value);
        return preg_match('/\A\+?[0-9][0-9 -]{5,18}\z/', $value) === 1 ? $value : null;
    }

    /** Format only (no mod-97 check: the IBANs of the demo data are invented). Spaces are removed. */
    public static function iban(string $value): ?string
    {
        $value = strtoupper(preg_replace('/\s+/', '', $value) ?? '');
        return preg_match('/\A[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}\z/', $value) === 1 ? $value : null;
    }

    /** A real calendar date written YYYY-MM-DD. */
    public static function date(string $value): ?string
    {
        return preg_match('/\A([0-9]{4})-([0-9]{2})-([0-9]{2})\z/', $value, $p) === 1
            && checkdate((int) $p[2], (int) $p[3], (int) $p[1]) ? $value : null;
    }

    /** A date and time from <input type="datetime-local">, as "YYYY-MM-DD HH:MM:SS". */
    public static function dateTime(string $value): ?string
    {
        if (preg_match('/\A(\d{4}-\d{2}-\d{2})[T ]([01]\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?\z/', trim($value), $p) !== 1
            || self::date($p[1]) === null) {
            return null;
        }
        return $p[1] . ' ' . $p[2] . ':' . $p[3] . ':' . ($p[4] ?? '00');
    }

    /** A decimal number as text, so that no digit is lost on the way to DECIMAL($digits, $scale). A comma is accepted. */
    public static function decimal(string $value, int $digits, int $scale, bool $negative = false): ?string
    {
        $value = str_replace(',', '.', trim($value));
        return preg_match('/\A' . ($negative ? '-?' : '') . '(?:\d{1,' . ($digits - $scale) . '}(?:\.\d{1,' . $scale . '})?|\.\d{1,' . $scale . '})\z/', $value) === 1
            ? $value : null;
    }

    /** A whole number inside a range. */
    public static function int(string $value, int $min, int $max): ?int
    {
        $n = filter_var($value, FILTER_VALIDATE_INT, ['options' => ['min_range' => $min, 'max_range' => $max]]);
        return $n === false ? null : $n;
    }

    /** A positive BIGINT key (reading_id, event_id). */
    public static function bigId(string $value): ?int
    {
        return self::int($value, 1, PHP_INT_MAX);
    }

    /** Optional free text: null when empty; throws when it is too long or not valid text. Line breaks are allowed. */
    public static function note(string $value, int $max): ?string
    {
        $value = trim(str_replace("\r\n", "\n", $value));
        if ($value === '') {
            return null;
        }
        if (preg_match('/\A[^\x00-\x09\x0B-\x1F\x7F]{1,' . $max . '}\z/u', $value) !== 1) {
            throw Ui::invalid('the text may have at most ' . $max . ' characters.');
        }
        return $value;
    }

    /** A positive INT key. */
    public static function id(string $value): ?int
    {
        $id = filter_var($value, FILTER_VALIDATE_INT, ['options' => ['min_range' => 1, 'max_range' => 2147483647]]);
        return $id === false ? null : $id;
    }

    /** Length as NVARCHAR counts it; null when the text is not valid UTF-8. */
    public static function utf16Length(string $value): ?int
    {
        if (preg_match('//u', $value) !== 1) {
            return null;
        }
        return strlen((string) iconv('UTF-8', 'UTF-16LE', $value)) >> 1;
    }

    /**
     * A new password, or the reason it is refused. At least 8 characters as SQL Server's LEN() counts them (trailing
     * spaces do not count) and at most 128, the size of the parameter; Auth::login() uses the same limit.
     */
    public static function passwordProblem(string $password, string $repeat): ?string
    {
        if (self::utf16Length($password) === null || str_contains($password, "\0")) {
            return 'The password contains characters that are not allowed.';
        }
        if (self::utf16Length(rtrim($password, ' ')) < 8) {
            return 'The password needs at least 8 characters.';
        }
        if (self::utf16Length($password) > 128) {
            return 'The password is too long (at most 128 characters).';
        }
        return $password === $repeat ? null : 'The two passwords are not the same.';
    }
}
