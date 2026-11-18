<?php
declare(strict_types=1);
// Unit test of the error mapping. No database needed:   php tests/errors_test.php
foreach (['Config', 'DbError', 'Errors'] as $c) {
    require __DIR__ . '/../src/' . $c . '.php';
}
use Mdms\DbError;
use Mdms\Errors;

$fail = 0;
function check(string $name, bool $ok, string $detail = ''): void
{
    global $fail;
    echo ($ok ? 'PASS ' : 'FAIL ') . $name . ($ok ? '' : '  ' . $detail) . "\n";
    if (!$ok) { $fail++; }
}
$prefix = '[Microsoft][ODBC Driver 18 for SQL Server][SQL Server]';

check('driver prefix is removed', Errors::clean($prefix . 'Login failed.') === 'Login failed.');
check('text without prefix is kept', Errors::clean('Something') === 'Something');

$catalog = [50001 => ['not_found', 404], 50002 => ['permission', 403], 50003 => ['state', 409], 50004 => ['input', 422],
            50005 => ['duplicate', 409], 50006 => ['login', 401], 50007 => ['busy', 503], 50008 => ['history', 402]];
foreach ($catalog as $code => [$cat, $http]) {
    $e = Errors::classify($code, 'text');
    check("THROW $code -> $cat / $http", $e !== null && $e->category() === $cat && $e->httpStatus() === $http && $e->sqlCode() === $code);
}
for ($n = 51001; $n <= 51012; $n++) {
    $e = Errors::classify(50000, "[$n] A rule was broken.");
    check("guard trigger [$n]", $e !== null && $e->category() === DbError::GUARD && $e->sqlCode() === $n && $e->getUserMessage() === 'A rule was broken.');
}
check('[51013] is not a project error', Errors::classify(50000, '[51013] x') === null);
check('[51000] is not a project error', Errors::classify(50000, '[51000] x') === null);
check('plain error 50000 is unknown', Errors::classify(50000, 'free text') === null);
check('3609 (rollback after the trigger) is unknown', Errors::classify(3609, 'The transaction ended in the trigger.') === null);

// the first error wins: a guard trigger gives [51004] and then 3609
$list = [
    ['SQLSTATE' => '42000', 'code' => 50000, 'message' => $prefix . '[51004] A meter can become ACTIVE only with its 3 certificates approved.'],
    ['SQLSTATE' => '25000', 'code' => 3609,  'message' => $prefix . 'The transaction ended in the trigger. The batch has been aborted.'],
];
$e = Errors::fromSqlsrv($list, 'test');
check('trigger error list -> 51004 from the first entry', $e->category() === DbError::GUARD && $e->sqlCode() === 51004);
check('...and the message has no driver prefix', !str_contains($e->getUserMessage(), 'ODBC'));

// unknown errors never leak SQL text to the user
$secret = "Invalid object name 'dbo.USER_ACCOUNT'.";
$e = Errors::fromSqlsrv([['SQLSTATE' => '42S02', 'code' => 208, 'message' => $prefix . $secret]], 'test');
check('unknown error -> server category, HTTP 500', $e->category() === DbError::SERVER && $e->httpStatus() === 500);
check('unknown error hides the SQL text', !str_contains($e->getUserMessage(), 'USER_ACCOUNT') && $e->reference() !== '');
$e = Errors::fromSqlsrv(null, 'test');
check('no error information -> server category', $e->category() === DbError::SERVER);

echo $fail === 0 ? "errors_test.php: all passed\n" : "errors_test.php: $fail FAILED\n";
exit($fail === 0 ? 0 : 1);
