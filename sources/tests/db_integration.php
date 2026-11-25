<?php
declare(strict_types=1);
/**
 * Integration test of Db / Errors against the real database. Run inside the dev container (it needs the sqlsrv driver
 * and DB_* in the environment):   php tests/db_integration.php
 * Every call below changes nothing: it is either a read, or a call that the database refuses (and rolls back).
 * The only writes are the audit rows of two sp_Login calls.
 */
foreach (['Config', 'DbError', 'Errors', 'Connect', 'Db', 'Auth', 'Csrf', 'Menu', 'View', 'Validate'] as $c) {
    require __DIR__ . '/../src/' . $c . '.php';
}
use Mdms\Db;
use Mdms\DbError;

$fail = 0;
function check(string $name, bool $ok, string $detail = ''): void
{
    global $fail;
    echo ($ok ? 'PASS ' : 'FAIL ') . $name . ($ok ? '' : '  ' . $detail) . "\n";
    if (!$ok) { $fail++; }
}
/** @return array{0:?DbError,1:array} */
function attempt(callable $f): array
{
    try { return [null, $f()]; } catch (DbError $e) { return [$e, []]; }
}
function expect(string $name, string $category, int $code, callable $f): void
{
    [$e] = attempt($f);
    check($name, $e !== null && $e->category() === $category && $e->sqlCode() === $code,
        $e === null ? 'no error' : $e->category() . '/' . $e->sqlCode() . ' ' . $e->getUserMessage());
}

$pw = Db::nv('Passw0rd!23', 128);
$officer = (int) Db::row('sp_Login', ['officer1@mdms.cy', $pw], false)['user_id'];
$consumerRow = Db::row('sp_Login', ['consumer1@example.cy', $pw], false);
$consumer = (int) $consumerRow['user_id'];
check('sp_Login returns the user row without any password column',
    isset($consumerRow['role_code']) && !isset($consumerRow['password_hash']) && !isset($consumerRow['password']));

$as = static function (int $uid): void { $_SESSION = ['uid' => $uid]; };

// --- the connection really is the restricted user
check('connection runs as mdms_php (not the owner)', Db::currentUser() === 'mdms_php', Db::currentUser());

// --- no session: no actor
unset($_SESSION);
[$e] = attempt(fn() => Db::callAsActor('sp_RunVEE', ['2026-10-30', '2026-10-31']));
check('callAsActor without a login is refused', $e !== null && $e->category() === DbError::PERMISSION);

// --- procedure name whitelist
foreach (['sp_x; DROP TABLE USER_ACCOUNT', 'DROP', 'sp_', 'dbo.sp_Login', "sp_Login'"] as $bad) {
    try { Db::call($bad); check("procedure name '$bad' is refused", false); }
    catch (\InvalidArgumentException $e) { check("procedure name '$bad' is refused", true); }
}

// --- the error catalog, with real database errors (nothing is committed)
$as($officer);
expect('50001 not found (reading 999999999)', DbError::NOT_FOUND, 50001, fn() => Db::callAsActor('sp_AcceptSuspectReading', [999999999]));
expect('50003 wrong state (a VALID reading cannot be accepted)', DbError::STATE, 50003, fn() => Db::callAsActor('sp_AcceptSuspectReading', [1]));
expect('50004 bad input (window with from > to)', DbError::INPUT, 50004, fn() => Db::callAsActor('sp_RunVEE', ['2026-10-31 00:00:00', '2026-10-30 00:00:00']));
$as($consumer);
expect('50002 permission (a consumer runs VEE)', DbError::PERMISSION, 50002, fn() => Db::callAsActor('sp_RunVEE', ['2026-10-30 00:00:00', '2026-10-31 00:00:00']));

// --- a guard trigger: confirming a meter that has no certificates -> [51004], rolled back
$as($officer);
$meters = Db::rows('sp_ListMeters', [null, null, null, 1, 500]);
check('a procedure with many rows returns them (sp_ListMeters)', count($meters) >= 12, (string) count($meters));
$pending = null;
foreach ($meters as $m) { if (($m['serial_number'] ?? '') === 'SN-TEST-0001') { $pending = (int) $m['meter_id']; } }
if ($pending === null) {
    echo "SKIP guard trigger test: meter SN-TEST-0001 (created by tests.sql) does not exist; run tests.sql first\n";
} else {
    expect('[51004] guard trigger surfaces with its own number', DbError::GUARD, 51004,
        fn() => Db::callAsActor('sp_ConfirmMeter', [$pending, 'APPROVE', Db::nv(null, 500)]));
    // the connection is still usable after the rolled-back call
    $again = Db::rows('sp_ListMeters', [null, null, null, 1, 5]);
    check('the connection works after a trigger rollback', count($again) === 5, (string) count($again));
}

// --- Greek text survives the round trip through NVARCHAR
$mine = Db::row('sp_GetMyProfile', []);
check('Greek full name is intact (sp_GetMyProfile)', $mine !== null && preg_match('/\p{Greek}/u', (string) ($mine['full_name'] ?? '')) === 1,
    json_encode($mine, JSON_UNESCAPED_UNICODE) ?: '');

echo $fail === 0 ? "db_integration.php: all passed\n" : "db_integration.php: $fail FAILED\n";
exit($fail === 0 ? 0 : 1);
