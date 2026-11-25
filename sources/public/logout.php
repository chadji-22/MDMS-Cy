<?php
declare(strict_types=1);
require __DIR__ . '/../src/bootstrap.php';

use Mdms\Auth;
use Mdms\Csrf;
use Mdms\View;

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: ' . View::url('/home.php'), true, 303);   // logging out is a POST with a token, never a link
    exit;
}
Csrf::verify();
Auth::logout();
header('Location: ' . View::url('/login.php'), true, 303);
exit;
