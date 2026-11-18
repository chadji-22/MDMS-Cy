<?php
declare(strict_types=1);

namespace Mdms;

/**
 * Translates what sqlsrv_errors() returns into a DbError, following the error catalog of the project:
 *   50001 not found · 50002 permission · 50003 wrong state · 50004 bad input · 50005 duplicate ·
 *   50006 login failed · 50007 busy · 50008 history not bought     (THROW in the procedures: the native error number)
 *   [51001] ... [51012]                                            (guard triggers: RAISERROR gives number 50000,
 *                                                                   the number is the bracketed prefix of the text,
 *                                                                   and a second error 3609 follows the rollback)
 * Known errors show the text the database wrote for the user. Anything else shows a neutral message with a
 * reference; the technical text goes to the server log only, so no SQL detail reaches the browser.
 */
final class Errors
{
    private const BY_CODE = [
        50001 => [DbError::NOT_FOUND,  404],
        50002 => [DbError::PERMISSION, 403],
        50003 => [DbError::STATE,      409],
        50004 => [DbError::INPUT,      422],
        50005 => [DbError::DUPLICATE,  409],
        50006 => [DbError::LOGIN,      401],
        50007 => [DbError::BUSY,       503],
        50008 => [DbError::HISTORY,    402],
    ];

    /** @param array<int,array<string|int,mixed>>|null $errors the value of sqlsrv_errors() */
    public static function fromSqlsrv(?array $errors, string $context): DbError
    {
        $errors = $errors ?? [];
        $first = null;
        foreach ($errors as $e) {
            $text = self::clean((string) ($e['message'] ?? $e[2] ?? ''));
            $code = (int) ($e['code'] ?? $e[1] ?? 0);
            $classified = self::classify($code, $text);
            if ($classified !== null) {
                return $classified;
            }
            if ($first === null) {
                $first = [$code, (string) ($e['SQLSTATE'] ?? $e[0] ?? ''), $text];
            }
        }
        // unknown: log the detail, show a neutral message
        $ref = bin2hex(random_bytes(4));
        $detail = $first === null ? 'no error information' : sprintf('code=%d state=%s %s', $first[0], $first[1], $first[2]);
        error_log(sprintf('[MDMS %s] %s: %s', $ref, $context, $detail));
        $msg = Config::flag('APP_DEBUG') && $first !== null
            ? 'Technical error (debug mode): ' . $first[2]
            : 'The operation could not be completed. If it keeps happening, quote reference ' . $ref . '.';
        return new DbError(DbError::SERVER, 0, 500, $msg, $ref);
    }

    /** Public so the unit test can feed it synthetic errors. */
    public static function classify(int $code, string $text): ?DbError
    {
        if (isset(self::BY_CODE[$code])) {
            [$cat, $http] = self::BY_CODE[$code];
            return new DbError($cat, $code, $http, $text);
        }
        // guard triggers: "[51004] A meter can become ACTIVE ..." (number 50000)
        if ($code === 50000 && preg_match('/^\[(51(?:0(?:0[1-9]|1[0-2])))\]\s*(.*)$/s', $text, $m) === 1) {
            return new DbError(DbError::GUARD, (int) $m[1], 409, trim($m[2]));
        }
        return null;
    }

    /** Removes the driver prefix "[Microsoft][ODBC Driver 18 for SQL Server][SQL Server]" and trims. */
    public static function clean(string $message): string
    {
        $message = preg_replace('/^(?:\[Microsoft\])?\[ODBC[^\]]*\]\[SQL Server\]/', '', $message) ?? $message;
        return trim($message);
    }
}
