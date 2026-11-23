<?php
declare(strict_types=1);

namespace Mdms;

/** Small output and request helpers shared by the market, dso and tso pages. Everything returned as HTML is escaped. */
final class Ui
{
    /** <option> list from a value => label map. */
    public static function options(array $map, string|int|null $selected): string
    {
        $html = '';
        foreach ($map as $value => $label) {
            $html .= '<option value="' . View::h($value) . '"' . ((string) $value === (string) $selected ? ' selected' : '') . '>'
                   . View::h($label) . '</option>';
        }
        return $html;
    }

    public static function num(mixed $v, int $decimals = 3): string
    {
        return $v === null || $v === '' ? '—' : number_format((float) $v, $decimals, '.', ' ');
    }

    /** "2026-11-22 10:15:00" -> "2026-11-22 10:15" (UTC, as stored). */
    public static function ts(mixed $v): string
    {
        return $v === null || $v === '' ? '—' : substr((string) $v, 0, 16);
    }

    /** A field of the query string as a string (a crafted array counts as empty). */
    public static function get(string $name): string
    {
        $v = $_GET[$name] ?? '';
        return is_string($v) ? trim($v) : '';
    }

    /** Previous / next links. The procedures return no total, so a full page means there may be another one. */
    public static function pager(string $path, array $query, int $page, int $rows, int $size): string
    {
        $link = static fn(int $p, string $text): string =>
            '<a href="' . View::h($path . '?' . http_build_query(['page' => $p] + $query)) . '">' . View::h($text) . '</a>';
        $html = [];
        if ($page > 1) {
            $html[] = $link($page - 1, '‹ Previous');
        }
        if ($page > 1 || $rows >= $size) {
            $html[] = 'page ' . $page;
        }
        if ($rows >= $size) {
            $html[] = $link($page + 1, 'Next ›');
        }
        return $html === [] ? '' : '<p class="muted">' . implode(' · ', $html) . '</p>';
    }

    public static function badge(string $text): string
    {
        $class = match ($text) {
            'WARNING', 'SUSPECT', 'SKIPPED', 'UNMATCHED', 'QUARANTINED', 'OVERDUE' => 'warning',
            'CRITICAL', 'ERROR', 'FAILED', 'COMM_ERROR', 'OVERLOADED' => 'critical',
            default => '',
        };
        return '<span class="badge ' . $class . '">' . View::h($text) . '</span>';
    }

    /** Keeps the result of a POST for the page that follows the redirect (shown once). */
    public static function keep(string $key, array $data): void
    {
        $_SESSION['kept'][$key] = $data;
    }

    public static function kept(string $key): ?array
    {
        $data = $_SESSION['kept'][$key] ?? null;
        unset($_SESSION['kept'][$key]);
        return is_array($data) ? $data : null;
    }

    public static function redirect(string $path): never
    {
        header('Location: ' . $path, true, 303);
        exit;
    }

    /** An input error raised by the page, shown like one of the database. */
    public static function invalid(string $message): DbError
    {
        return new DbError(DbError::INPUT, 50004, 422, 'Invalid input: ' . $message);
    }

    /** The transformer tree as id => "— — name (level n)" for a <select>; optionally only one level. */
    public static function transformerOptions(array $tree, ?int $onlyLevel = null): array
    {
        $map = [];
        foreach ($tree as $t) {
            if ($onlyLevel === null || (int) $t['level'] === $onlyLevel) {
                $map[(int) $t['transformer_id']] = ($onlyLevel === null ? str_repeat('— ', (int) $t['depth']) : '')
                    . $t['name'] . ' (level ' . $t['level'] . ')';
            }
        }
        return $map;
    }

    /** JSON answer of a data endpoint. Escaped so that it stays harmless even if a browser shows it as HTML. */
    public static function json(array $data, int $status = 200): never
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=UTF-8');
        header('X-Content-Type-Options: nosniff');
        header('Cache-Control: no-store');
        echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP | JSON_INVALID_UTF8_SUBSTITUTE | JSON_THROW_ON_ERROR);
        exit;
    }

    /** Guard of a data endpoint: answers 401 / 403 as JSON instead of sending a program to the login page. */
    public static function jsonRole(string ...$roles): void
    {
        if (!Auth::check()) {
            self::json(['error' => 'You must be logged in.'], 401);
        }
        if (!in_array(Auth::role(), $roles, true)) {
            self::json(['error' => 'Your role does not allow this.'], 403);
        }
        if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
            header('Allow: GET');
            self::json(['error' => 'Only GET is supported.'], 405);
        }
    }
}
