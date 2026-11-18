<?php
declare(strict_types=1);

/**
 * First line of every page:   require __DIR__ . '/../src/bootstrap.php';     (adjust the ../ to the page's depth)
 * Loads the classes, starts the session and installs the last-resort error handler.
 * Plain PHP >= 8.1: no Composer, no framework; every path is built from __DIR__ so the application runs
 * the same under Apache, XAMPP or `php -S`.
 */

foreach (['Config', 'DbError', 'Errors', 'Db', 'Auth', 'Csrf', 'Menu', 'View'] as $class) {
    require_once __DIR__ . '/' . $class . '.php';
}

use Mdms\Config;
use Mdms\DbError;
use Mdms\View;

// never print PHP errors into the page; they go to the server log
ini_set('display_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

set_exception_handler(static function (\Throwable $e): void {
    if ($e instanceof DbError) {
        View::fail($e->httpStatus(), $e->category() === DbError::SERVER ? 'Service problem' : 'Request refused', $e->getUserMessage());
    }
    $ref = bin2hex(random_bytes(4));
    error_log(sprintf('[MDMS %s] uncaught %s: %s in %s:%d', $ref, get_class($e), $e->getMessage(), $e->getFile(), $e->getLine()));
    $detail = Config::flag('APP_DEBUG') ? ' (' . $e->getMessage() . ')' : '';
    View::fail(500, 'Service problem', 'Something went wrong. Quote reference ' . $ref . ' if it keeps happening.' . $detail);
});

Mdms\Auth::startSession();
