<?php
declare(strict_types=1);

namespace Mdms;

/**
 * The shared layout and the output helpers. Every value printed into HTML goes through View::h().
 *
 * Page skeleton:
 *     require __DIR__ . '/../../src/bootstrap.php';
 *     Mdms\Auth::requireRole('CONSUMER');
 *     Mdms\View::header('My premises');
 *     ... HTML, every value as <?= Mdms\View::h($value) ?> ...
 *     Mdms\View::footer();
 */
final class View
{
    /** Extra Content-Security-Policy sources a page needs (e.g. the Leaflet map: img-src tiles). */
    public static array $cspExtra = [];

    /** HTML-escape. Use for EVERY value that comes from the database, the request or the session. */
    public static function h(mixed $value): string
    {
        return htmlspecialchars((string) ($value ?? ''), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    }

    private static function securityHeaders(): void
    {
        if (headers_sent()) {
            return;
        }
        $csp = ['default-src' => ["'self'"], 'img-src' => ["'self'", 'data:'], 'style-src' => ["'self'"],
                'script-src' => ["'self'"], 'frame-ancestors' => ["'none'"], 'form-action' => ["'self'"], 'base-uri' => ["'self'"]];
        foreach (self::$cspExtra as $directive => $sources) {
            $csp[$directive] = array_merge($csp[$directive] ?? [], (array) $sources);
        }
        $line = [];
        foreach ($csp as $d => $s) {
            $line[] = $d . ' ' . implode(' ', array_unique($s));
        }
        header('Content-Security-Policy: ' . implode('; ', $line));
        header('X-Content-Type-Options: nosniff');
        header('X-Frame-Options: DENY');
        if (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') {
            header('Strict-Transport-Security: max-age=31536000');
        }
        header('Referrer-Policy: same-origin');
        header('Cache-Control: no-store');
    }

    /** One-time messages that survive a redirect: Flash after a POST, shown on the next page. */
    public static function flash(string $type, string $message): void
    {
        $_SESSION['flash'][] = ['type' => $type === 'error' ? 'error' : 'ok', 'msg' => $message];
    }

    public static function header(string $title): void
    {
        self::securityHeaders();
        header('Content-Type: text/html; charset=UTF-8');
        $items = Auth::check() ? Menu::forRole(Auth::role()) : [];
        echo '<!doctype html><html lang="en"><head><meta charset="utf-8">'
           . '<meta name="viewport" content="width=device-width, initial-scale=1">'
           . '<title>' . self::h($title) . ' · MDMS-Cy</title>'
           . '<link rel="stylesheet" href="/assets/style.css"></head><body>';
        echo '<header class="top"><a class="brand" href="/home.php">MDMS-Cy</a>';
        if (Auth::check()) {
            echo '<nav><a href="/home.php">Home</a>';
            foreach ($items as $it) {
                echo '<a href="' . self::h($it['href']) . '">' . self::h($it['label']) . '</a>';
            }
            echo '</nav><form class="logout" method="post" action="/logout.php">' . Csrf::field()
               . '<span class="who">' . self::h(Auth::name()) . ' · ' . self::h(Auth::role())
               . '</span><button type="submit">Log out</button></form>';
        }
        echo '</header><main><h1>' . self::h($title) . '</h1>';
        foreach ($_SESSION['flash'] ?? [] as $f) {
            echo '<p class="flash ' . self::h($f['type']) . '" role="status">' . self::h($f['msg']) . '</p>';
        }
        unset($_SESSION['flash']);
    }

    public static function footer(): void
    {
        echo '</main><footer>EPL342 · Group 10 · MDMS-Cy</footer></body></html>';
    }

    /** Shows an error message inside the page (after a failed procedure call). */
    public static function error(DbError $e): void
    {
        echo '<p class="flash error" role="alert">' . self::h($e->getUserMessage()) . '</p>';
    }

    /** Ends the request with an error page and an HTTP status. */
    public static function fail(int $status, string $title, string $message): never
    {
        if (!headers_sent()) {
            http_response_code($status);
        }
        self::header($title);
        echo '<p class="flash error" role="alert">' . self::h($message) . '</p>'
           . '<p><a href="/home.php">Back to the home page</a></p>';
        self::footer();
        exit;
    }
}
