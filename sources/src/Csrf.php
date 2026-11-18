<?php
declare(strict_types=1);

namespace Mdms;

/**
 * Cross-site request forgery guard. Every <form method="post"> contains Csrf::field() and every POST handler
 * starts with Csrf::verify(). One token per session, compared in constant time.
 */
final class Csrf
{
    public static function token(): string
    {
        if (empty($_SESSION['csrf'])) {
            $_SESSION['csrf'] = bin2hex(random_bytes(32));
        }
        return (string) $_SESSION['csrf'];
    }

    public static function field(): string
    {
        return '<input type="hidden" name="_csrf" value="' . View::h(self::token()) . '">';
    }

    /** Ends the request with 403 unless the posted token is the session's token. */
    public static function verify(): void
    {
        $sent = (string) ($_POST['_csrf'] ?? '');
        if ($sent === '' || empty($_SESSION['csrf']) || !hash_equals((string) $_SESSION['csrf'], $sent)) {
            View::fail(403, 'Form expired', 'The form is no longer valid. Go back, reload the page and try again.');
        }
    }
}
