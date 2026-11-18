<?php
declare(strict_types=1);
// Developer check only: answers 404 unless APP_DEBUG=1. Shows that the database is reachable and which SQL user the
// connection runs as (it must be the role member mdms_php, not the owner).
require __DIR__ . '/../src/bootstrap.php';

if (!Mdms\Config::flag('APP_DEBUG')) {
    http_response_code(404);
    exit;
}
header('Content-Type: application/json');
echo json_encode(['ok' => true, 'sql_user' => Mdms\Db::currentUser(), 'php' => PHP_VERSION], JSON_UNESCAPED_UNICODE);
