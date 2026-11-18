<?php
declare(strict_types=1);
require __DIR__ . '/../src/bootstrap.php';

use Mdms\Auth;
use Mdms\Csrf;

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Location: /home.php', true, 303);   // logging out is a POST with a token, never a link
    exit;
}
Csrf::verify();
Auth::logout();
header('Location: /login.php', true, 303);
exit;
