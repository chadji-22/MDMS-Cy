<?php
declare(strict_types=1);
/**
 * B10: static audit of every page against the rules of sources/README.md. No database needed:   php tests/audit_pages.php
 * It reads the PHP files and the procedure signatures of ../procedures_*.sql (or ../sql/) and reports, per page:
 *   guard      no Auth::requireRole / requireLogin / Ui::jsonRole (public pages are listed below)
 *   csrf       the page reads $_POST without Csrf::verify(), or a POST form has no Csrf::field()
 *   sql        a sqlsrv_ function outside src/Db.php
 *   call       a procedure that does not exist, or a wrong number of parameters
 *   escape     a printed expression that is not obviously escaped (to be read by a person)
 *   inline     an inline script, style or event handler (blocked by the Content-Security-Policy)
 *   actor      an actor_user_id taken from the request
 */
$root = dirname(__DIR__);
$public = ['login.php', 'logout.php', 'index.php', 'health.php', 'register.php', 'register-technician.php'];

// --- signatures: procedure => [number of parameters without OUTPUT, required, has actor]
$sql = '';
foreach (array_merge(glob($root . '/../procedures_*.sql') ?: [], glob($root . '/../sql/procedures_*.sql') ?: []) as $file) {
    $sql .= str_replace("\r\n", "\n", (string) file_get_contents($file)) . "\n";
}
$sig = [];
preg_match_all('/CREATE OR ALTER PROCEDURE \[dbo\]\.\[(sp_\w+)\]\s*\n(.*?)\nAS\b/s', $sql, $m, PREG_SET_ORDER);
foreach ($m as [, $name, $list]) {
    $list = preg_replace('/--[^\n]*/', '', $list) ?? '';
    preg_match_all('/@(\w+)\s+([A-Z]+(?:\([^)]*\))?)([^@]*)/', $list, $p, PREG_SET_ORDER);
    $max = $required = 0;
    $first = $p[0][1] ?? '';
    foreach ($p as [, , , $rest]) {
        $max++;
        if (!str_contains($rest, '=')) {
            $required = $max;                    // positional call: everything up to the last required one is needed
        }
    }
    $sig[$name] = [$max, $required, $first === 'actor_user_id'];
}
if (count($sig) < 100) {
    fwrite(STDERR, "The procedure files were not found next to sources/.\n");
    exit(2);
}

/** Number of top-level elements of the array literal that starts at token $i ('['); null when it is not a literal. */
function elements(array $t, int &$i): ?int
{
    if ($t[$i] !== '[') {
        return null;
    }
    $depth = 0;
    $count = 0;
    $something = false;
    for (; isset($t[$i]); $i++) {
        $s = is_array($t[$i]) ? $t[$i][1] : $t[$i];
        if (is_array($t[$i]) && in_array($t[$i][0], [T_WHITESPACE, T_COMMENT, T_DOC_COMMENT], true)) {
            continue;
        }
        if (in_array($s, ['[', '(', '{'], true)) {
            $something = $something || $depth > 0;
            $depth++;
        } elseif (in_array($s, [']', ')', '}'], true)) {
            if (--$depth === 0) {
                return $count + ($something ? 1 : 0);
            }
        } elseif ($s === ',' && $depth === 1) {
            $count++;
            $something = false;
        } elseif ($s === '...' && $depth === 1) {
            return null;
        } else {
            $something = true;
        }
    }
    return null;
}

$problems = [];
$calls = 0;
$used = [];
$files = new RegexIterator(new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS)), '/\.php$/');
foreach ($files as $file) {
    $rel = str_replace('\\', '/', substr((string) $file, strlen($root) + 1));
    if (!preg_match('#^(public|areas|src)/#', $rel)) {
        continue;
    }
    $code = (string) file_get_contents((string) $file);
    $page = str_starts_with($rel, 'public/');
    $report = static function (string $kind, string $text, int $line = 0) use (&$problems, $rel): void {
        $problems[] = sprintf('%-7s %s%s  %s', $kind, $rel, $line > 0 ? ':' . $line : '', $text);
    };
    $lineOf = static fn(int $offset): int => substr_count(substr($code, 0, $offset), "\n") + 1;

    // procedure calls
    $tokens = token_get_all($code);
    foreach ($tokens as $i => $t) {
        if (!is_array($t) || $t[0] !== T_CONSTANT_ENCAPSED_STRING || preg_match('/^[\'"](sp_\w+)[\'"]$/', $t[1], $n) !== 1) {
            continue;
        }
        $used[$n[1]] = true;                     // also when a page keeps the name in an array
        $before = '';
        for ($k = $i - 1; $k >= 0 && strlen($before) < 20; $k--) {
            $before = (is_array($tokens[$k]) ? $tokens[$k][1] : $tokens[$k]) . $before;
        }
        if (preg_match('/Db::(rows|row|call|callAsActor)\(\s*$/', $before, $b) !== 1) {
            continue;
        }
        $calls++;
                if (!isset($sig[$n[1]])) {
            $report('call', $n[1] . ' does not exist', $t[2]);
            continue;
        }
        $j = $i + 1;
        while (is_array($tokens[$j]) && $tokens[$j][0] === T_WHITESPACE) { $j++; }
        $given = 0;
        $actor = $b[1] !== 'call';
        if ($tokens[$j] === ',') {
            $j++;
            while (is_array($tokens[$j]) && $tokens[$j][0] === T_WHITESPACE) { $j++; }
            $given = elements($tokens, $j);
            if ($given === null) {
                $report('call', $n[1] . ': parameters are not a literal list, check by hand', $t[2]);
                continue;
            }
            $tail = '';
            for ($k = $j + 1; isset($tokens[$k]) && strlen($tail) < 12; $k++) {
                $tail .= is_array($tokens[$k]) ? $tokens[$k][1] : $tokens[$k];
            }
            if (preg_match('/^\s*,\s*false/', $tail) === 1) {
                $actor = false;
            }
        }
        [$max, $required, $hasActor] = $sig[$n[1]];
        $total = $given + ($actor ? 1 : 0);
        if ($actor && !$hasActor) {
            $report('call', $n[1] . ' takes no actor but is called with one', $t[2]);
        } elseif (!$actor && $hasActor && $required > 0 && !in_array($n[1], ['sp_RaiseTamperEvent', 'sp_RecordTransformerReading'], true)) {
            $report('call', $n[1] . ' needs the actor', $t[2]);
        }
        if ($total < $required || $total > $max) {
            $report('call', sprintf('%s: %d parameters given, %d to %d expected', $n[1], $total, $required, $max), $t[2]);
        }
    }

    if ($rel !== 'src/Db.php' && preg_match('/\bsqlsrv_(query|prepare|execute|connect)\b/', $code, $x, PREG_OFFSET_CAPTURE) === 1) {
        $report('sql', $x[0][0] . ' outside src/Db.php', $lineOf($x[0][1]));
    }
    if (preg_match('/\$_(POST|GET|REQUEST|COOKIE)\s*\[\s*[\'"]actor_user_id/', $code) === 1) {
        $report('actor', 'actor_user_id is read from the request');
    }
    if (!$page) {
        continue;
    }
    $name = substr($rel, strlen('public/'));
    if (!in_array($name, $public, true) && preg_match('/(Auth::requireRole|Auth::requireLogin|Ui::jsonRole)\s*\(/', $code) !== 1) {
        $report('guard', 'no page guard');
    }
    $readsPost = preg_match('/\$_POST|Validate::post\(|INPUT_POST|\$_FILES/', $code) === 1;
    if ($readsPost && preg_match('/Csrf::verify\(\)/', $code) !== 1) {
        $report('csrf', 'reads the form without Csrf::verify()');
    }
    preg_match_all('/<form\b[^>]*method="post"/i', $code, $forms, PREG_OFFSET_CAPTURE);
    foreach ($forms[0] as [, $offset]) {
        $end = strpos($code, '</form>', $offset);
        if ($end === false || !str_contains(substr($code, $offset, $end - $offset), 'Csrf::field()')) {
            $report('csrf', 'POST form without Csrf::field()', $lineOf($offset));
        }
    }
    if (preg_match('/<script(?![^>]*\bsrc=)|<style\b|\sstyle="|\son(click|change|submit|load|input)="/i', $code, $x, PREG_OFFSET_CAPTURE) === 1) {
        $report('inline', trim($x[0][0]), $lineOf($x[0][1]));
    }
    // printed expressions: accepted when every value in them goes through one of these
    preg_match_all('/<\?=\s*(.*?)\s*\?>/s', $code, $echo, PREG_OFFSET_CAPTURE | PREG_SET_ORDER);
    foreach ($echo as $e) {
        $x = $e[1][0];
        $safe = preg_replace('/(?:View::h|Ui::(?:options|badge|pager)|Csrf::field|C\\\\(?:options|premiseOptions)|count|\(int\)\s*)\s*(\((?:[^()]++|(?1))*\))/', 'S', $x) ?? $x;
        $safe = preg_replace('/\(int\)\s*\$\w+(?:->\w+|\[[^\]]*\])*(?:\s*\?\?\s*[^)\s]+)?/', 'S', $safe) ?? $safe;
        // what is left of "condition ? 'text' : 'text'" prints constants only: drop the condition
        $printed = preg_match('/^(.*?)\?(?!\?|->)(.*)$/s', $safe, $q) === 1 ? $q[2] : $safe;
        if (preg_match('/\$(?!self\b|path\b|coordinate\b|billed\b|meters\b|overloaded\b|suspects\b)\w+/', $printed) === 1) {
            $report('escape', trim($x), $lineOf($e[0][1]));
        }
    }
}

sort($problems);
// "escape" and "check by hand" are for a person to read; the rest are errors
$hard = array_filter($problems, static fn(string $p): bool => !str_starts_with($p, 'escape') && !str_contains($p, 'check by hand'));
foreach ($problems as $line) {
    echo in_array($line, $hard, true) ? 'ERROR  ' : 'review ', $line, "\n";
}
$unused = array_diff(array_keys(array_filter($sig, static fn(string $n): bool => !str_starts_with($n, 'sp__'), ARRAY_FILTER_USE_KEY)), array_keys($used));
sort($unused);
echo "\n", $calls, ' procedure calls checked, ', count($hard), ' errors, ', count($problems) - count($hard), " to review.\n";
echo 'Procedures no page calls (', count($unused), '): ', implode(', ', $unused), "\n";
exit($hard === [] ? 0 : 1);
