<?php
declare(strict_types=1);

namespace Mdms;

/**
 * The only door to the database. Every page talks to SQL Server through call() / callAsActor(), which send
 *   {CALL dbo.<name>(?, ?, ...)}      with bound parameters only
 * The procedure name is checked against a whitelist pattern; no value is ever concatenated into SQL.
 *
 * Rules for page authors (see sources/README.md):
 *   1. Use callAsActor() for every procedure whose first parameter is @actor_user_id: the actor is taken from
 *      the session, never from the request, so a user cannot act as somebody else.
 *   2. Text that may contain Greek or a password is sent as Db::nv(...) (NVARCHAR), not as a plain string.
 *   3. Catch DbError and show getUserMessage().
 */
final class Db
{
    /** @var resource|null */
    private static $conn = null;

    /** Typed parameter: a PHP string sent as NVARCHAR(length) (keeps Greek text and exact password bytes). */
    public static function nv(?string $value, int $length = 4000): array
    {
        return [$value, SQLSRV_PARAM_IN, SQLSRV_PHPTYPE_STRING('UTF-8'), SQLSRV_SQLTYPE_NVARCHAR((string) $length)];
    }

    /** Typed parameter: a PHP string sent as NVARCHAR(MAX), for long JSON. */
    public static function nvMax(?string $value): array
    {
        return [$value, SQLSRV_PARAM_IN, SQLSRV_PHPTYPE_STRING('UTF-8'), SQLSRV_SQLTYPE_NVARCHAR('max')];
    }

    /** @return resource */
    private static function conn()
    {
        if (self::$conn === null) {
            self::$conn = self::connect();
            register_shutdown_function(static function (): void {
                if (self::$conn !== null) {
                    sqlsrv_close(self::$conn);
                    self::$conn = null;
                }
            });
        }
        return self::$conn;
    }

    /** @return resource */
    private static function connect()
    {
        if (!function_exists('sqlsrv_connect')) {
            throw new DbError(DbError::SERVER, 0, 500, 'The PHP sqlsrv extension is not installed on this server.');
        }
        // Informational messages (PRINT, "rows affected") must not turn a successful call into an error.
        sqlsrv_configure('WarningsReturnAsErrors', 0);

        // from the settings, or from the Connect page (kept in the session): see Connect
        [$name, $user, $pass] = Connect::credentials();
        if ($name === '' || $user === '') {
            throw new DbError(DbError::SERVER, 0, 500, 'The database is not configured (DB_NAME / DB_USER / DB_PASS).');
        }
        $conn = sqlsrv_connect(Config::get('DB_HOST'), self::options($name, $user, $pass));
        if ($conn === false) {
            throw Errors::fromSqlsrv(sqlsrv_errors(), 'connect');
        }
        self::runAs($conn);
        return $conn;
    }

    /** sqlsrv_connect() options; the password is only passed through, never logged. */
    private static function options(string $name, string $user, string $pass): array
    {
        return [
            'Database'               => $name,
            'UID'                    => $user,
            'PWD'                    => $pass,
            'Encrypt'                => true,      // as the Lab 7 skeleton; ODBC Driver 17 would not encrypt otherwise
            'TrustServerCertificate' => Config::flag('DB_TRUST_CERT'),
            'CharacterSet'           => 'UTF-8',
            'ReturnDatesAsStrings'   => true,
            'LoginTimeout'           => 10,
            // EXECUTE AS below: SQL Server drops such a connection when the ODBC pool (on by default on Windows) reuses it
            'ConnectionPooling'      => false,
            'ApplicationIntent'      => 'ReadWrite',
            'APP'                    => 'MDMS-Cy web',
        ];
    }

    /**
     * Connect page: tries a database login (and the switch to DB_RUN_AS) without keeping the connection.
     * Returns null when it works, otherwise a message that is safe to show (no password, no SQL detail).
     */
    public static function test(string $name, string $user, string $pass): ?string
    {
        if (!function_exists('sqlsrv_connect')) {
            return 'The PHP sqlsrv extension is not installed on this server.';
        }
        sqlsrv_configure('WarningsReturnAsErrors', 0);
        $conn = sqlsrv_connect(Config::get('DB_HOST'), self::options($name, $user, $pass));
        if ($conn === false) {
            $errors = sqlsrv_errors() ?? [];
            $codes = array_map(static fn(array $e): int => (int) ($e['code'] ?? 0), $errors);
            if (in_array(4060, $codes, true)) {
                return 'The login works, but it cannot open the database "' . $name . '". Check the database name.';
            }
            if (in_array(18456, $codes, true)) {
                return 'Login failed: check the login name and the password.';
            }
            return Errors::fromSqlsrv($errors, 'connect page')->getUserMessage();   // logged with a reference
        }
        try {
            self::runAs($conn);
        } catch (DbError $e) {
            return 'The login works, but the database is not ready for the application (restricted user '
                . Config::get('DB_RUN_AS') . '): ' . $e->getUserMessage();
        }
        sqlsrv_close($conn);
        return null;
    }

    /** @param resource $conn */
    private static function runAs($conn): void
    {
        // Least privilege: from here on this connection is the login-less user of the role mdms_app.
        $runAs = Config::get('DB_RUN_AS');
        if ($runAs !== '') {
            if (preg_match('/^[A-Za-z_][A-Za-z0-9_]{0,63}$/', $runAs) !== 1) {
                throw new DbError(DbError::SERVER, 0, 500, 'DB_RUN_AS is not a valid user name.');
            }
            $st = sqlsrv_query($conn, "EXECUTE AS USER = '" . $runAs . "'"); // $runAs matched the pattern above
            if ($st === false) {
                // fail closed: never carry on as the database owner by accident
                $err = Errors::fromSqlsrv(sqlsrv_errors(), 'EXECUTE AS ' . $runAs);
                sqlsrv_close($conn);
                throw $err;
            }
            sqlsrv_free_stmt($st);
        }
    }

    /**
     * Calls a procedure and returns ALL its result sets: a list of sets, each a list of associative rows.
     * Every set is read and the statement is advanced to its end, because an error raised after the first
     * SELECT only shows when the next result is requested.
     *
     * @param array<int,mixed> $params values or Db::nv() typed parameters, in the procedure's order
     * @return array<int,array<int,array<string,mixed>>>
     */
    public static function call(string $proc, array $params = []): array
    {
        if (preg_match('/^sp_[A-Za-z0-9_]{1,100}$/', $proc) !== 1) {
            throw new \InvalidArgumentException('Invalid procedure name.');
        }
        $marks = $params === [] ? '' : implode(', ', array_fill(0, count($params), '?'));
        $sql = '{CALL dbo.' . $proc . '(' . $marks . ')}';

        $stmt = sqlsrv_query(self::conn(), $sql, array_values($params));
        if ($stmt === false) {
            throw Errors::fromSqlsrv(sqlsrv_errors(), $proc);
        }

        $sets = [];
        $next = true;
        while ($next === true) {
            if (sqlsrv_num_fields($stmt) > 0) {
                $rows = [];
                while (($row = sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC)) !== null) {
                    if ($row === false) {
                        $err = Errors::fromSqlsrv(sqlsrv_errors(), $proc);
                        sqlsrv_free_stmt($stmt);
                        throw $err;
                    }
                    $rows[] = $row;
                }
                $sets[] = $rows;
            }
            $next = sqlsrv_next_result($stmt);   // true = another result, null = done, false = an error
        }
        if ($next === false) {
            $err = Errors::fromSqlsrv(sqlsrv_errors(), $proc);
            sqlsrv_free_stmt($stmt);
            throw $err;
        }
        sqlsrv_free_stmt($stmt);
        return $sets;
    }

    /** Like call(), with @actor_user_id (the logged-in user) put first. Use this for every protected procedure. */
    public static function callAsActor(string $proc, array $params = []): array
    {
        array_unshift($params, Auth::userId());
        return self::call($proc, $params);
    }

    /** Rows of the first result set (empty list when the procedure returned none). */
    public static function rows(string $proc, array $params = [], bool $asActor = true): array
    {
        $sets = $asActor ? self::callAsActor($proc, $params) : self::call($proc, $params);
        return $sets[0] ?? [];
    }

    /** First row of the first result set, or null. */
    public static function row(string $proc, array $params = [], bool $asActor = true): ?array
    {
        return self::rows($proc, $params, $asActor)[0] ?? null;
    }

    /** Name of the SQL user this connection runs as (developer health check). */
    public static function currentUser(): string
    {
        $stmt = sqlsrv_query(self::conn(), 'SELECT USER_NAME() AS u');
        $row = $stmt === false ? null : sqlsrv_fetch_array($stmt, SQLSRV_FETCH_ASSOC);
        return is_array($row) ? (string) $row['u'] : '?';
    }
}
