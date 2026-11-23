<?php
declare(strict_types=1);
// A technician's own photo. The path comes from the database for the logged-in user, never from the request.
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Db, Upload, View};

Auth::requireRole('TECHNICIAN');

$path = Db::row('sp_GetMyProfile')['photo_path'] ?? null;
$file = Upload::locate($path, 'technician-photos');
if ($file === null) {
    View::fail(404, 'Photo unavailable', 'The photo file is not stored on this server.');
}
header('Content-Type: ' . (str_ends_with($file, '.png') ? 'image/png' : 'image/jpeg'));
header('Content-Length: ' . filesize($file));
header('X-Content-Type-Options: nosniff');
header("Content-Security-Policy: default-src 'none'");
header('Cache-Control: no-store');
readfile($file);
