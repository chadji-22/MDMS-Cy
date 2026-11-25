<?php
// MDMS-Cy: one-time check of the department web server before deploying the full app.
// Prints only facts about the PHP setup (no passwords, no configuration values, no phpinfo()).
// DELETE THIS FILE after you have copied its output.
header('Content-Type: text/plain; charset=UTF-8');
header('Cache-Control: no-store');

function line($label, $value) { echo str_pad($label, 34) . ': ' . $value . "\n"; }
function yn($b) { return $b ? 'yes' : 'NO'; }

echo "== MDMS-Cy server check ==\n";
line('PHP version', PHP_VERSION . (version_compare(PHP_VERSION, '8.1.0', '>=') ? '  (OK, >= 8.1)' : '  (TOO OLD: the app needs 8.1+)'));
line('Server API', PHP_SAPI);

// Which OS user runs PHP? (get_current_user() would only tell the file owner, so it is not used.)
$fileOwner = @fileowner(__FILE__);
$procUid = null;
if (function_exists('posix_geteuid')) {
    $procUid = posix_geteuid();
} else {
    $tmp = @tempnam(sys_get_temp_dir(), 'mdms');
    if ($tmp !== false) { $procUid = @fileowner($tmp); @unlink($tmp); }
}
$name = function ($uid) {
    if ($uid === null || $uid === false) return 'unknown';
    if (function_exists('posix_getpwuid')) { $p = @posix_getpwuid($uid); if ($p) return $p['name'] . " (uid $uid)"; }
    return "uid $uid";
};
line('PHP runs as', $name($procUid));
line('This file is owned by', $name($fileOwner));
if (function_exists('posix_getgroups')) {
    $groups = array_map(function ($g) { $i = @posix_getgrgid($g); return ($i ? $i['name'] : '?') . "($g)"; }, posix_getgroups());
    line('PHP user is in the groups', implode(', ', $groups));
}
$fileGroup = @filegroup(__FILE__);
if ($fileGroup !== false && function_exists('posix_getgrgid')) {
    $gi = @posix_getgrgid($fileGroup);
    line('This file belongs to group', ($gi ? $gi['name'] : '?') . "($fileGroup)");
}
if ($procUid === null || $procUid === false || $fileOwner === false) {
    line('PHP runs as the file owner', 'unknown (see the 600 test below)');
} else {
    line('PHP runs as the file owner', $procUid === $fileOwner ? 'YES' : 'NO (shared web user)');
}

echo "\n-- extensions --\n";
foreach (['sqlsrv', 'pdo_sqlsrv', 'fileinfo', 'mbstring', 'session', 'json', 'openssl', 'posix'] as $ext) {
    line($ext, yn(extension_loaded($ext)));
}

echo "\n-- settings --\n";
$ob = ini_get('open_basedir');
line('open_basedir', $ob === '' || $ob === false ? '(none)' : $ob);
$df = (string) ini_get('disable_functions');
line('disable_functions', $df === '' ? '(none)' : $df);
foreach (['display_errors', 'display_startup_errors', 'file_uploads', 'upload_max_filesize', 'post_max_size',
          'session.save_handler', 'session.save_path', 'session.cookie_secure'] as $k) {
    $v = ini_get($k);
    line($k, $v === '' || $v === false ? '(empty)' : $v);
}

echo "\n-- request --\n";
$https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off');
line('HTTPS', yn($https));
line('SCRIPT_NAME', htmlspecialchars($_SERVER['SCRIPT_NAME'] ?? '?'));
line('Real folder of this file', __DIR__);

echo "\n-- file access outside the web folder --\n";
// Expects ~/mdms_probe.txt (chmod 644). This file sits in ~/public_html or in ~/probe (reached through a symlink).
$candidates = [dirname(__DIR__) . '/mdms_probe.txt', dirname(__DIR__, 2) . '/mdms_probe.txt'];
$found = null;
foreach ($candidates as $c) { if (@is_file($c)) { $found = $c; break; } }
line('~/mdms_probe.txt readable by PHP', $found !== null ? yn(@is_readable($found)) . "  ($found)" : 'NOT FOUND (did you create it?)');
$home = $found !== null ? dirname($found) : dirname(__DIR__);
line('home folder writable by PHP', yn(@is_writable($home)));

// The deciding test for the password file: can PHP read a file that only you may read (chmod 600)?
$p600 = $home . '/mdms_probe600.txt';
if (!@file_exists($p600)) {
    line('~/mdms_probe600.txt (chmod 600)', 'NOT FOUND (did you create it?)');
} else {
    $ok = @file_get_contents($p600) !== false;
    line('~/mdms_probe600.txt (chmod 600)', $ok ? 'READABLE -> config.local.php can be chmod 600 (private)'
                                              : 'NOT readable -> PHP is a shared user: STOP and decide (see notes)');
}

echo "\nDone. Copy everything above, then delete this file (and the probe files).\n";
