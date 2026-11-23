<?php
declare(strict_types=1);

namespace Mdms;

/**
 * Uploaded files. They are stored in sources/var/<folder>/ (outside the web root, git-ignored) under a random name;
 * the name and the type sent by the browser are never used. The database keeps "<folder>/<random>.<ext>".
 */
final class Upload
{
    public const MAX_BYTES = 2 * 1024 * 1024;
    public const PDF   = ['application/pdf' => 'pdf'];
    public const IMAGE = ['image/jpeg' => 'jpg', 'image/png' => 'png'];

    private static function root(): string
    {
        return dirname(__DIR__) . '/var/';
    }

    /**
     * A request larger than post_max_size reaches PHP with an empty $_POST, so the CSRF check would answer "form
     * expired". Call this before Csrf::verify() on pages with a file.
     */
    public static function rejectOversized(): void
    {
        if ($_POST === [] && (int) ($_SERVER['CONTENT_LENGTH'] ?? 0) > 0) {
            View::fail(413, 'File too large', 'The file is too large. Go back and choose one of at most 2 MB.');
        }
    }

    /** Why the file cannot be accepted, or null when it is fine. @param array<string,string> $types */
    public static function problem(string $field, array $types): ?string
    {
        $f = $_FILES[$field] ?? null;
        if ($f === null || !is_string($f['tmp_name']) || $f['error'] === UPLOAD_ERR_NO_FILE) {
            return 'Choose a file.';
        }
        if ($f['error'] === UPLOAD_ERR_INI_SIZE || $f['error'] === UPLOAD_ERR_FORM_SIZE || $f['size'] > self::MAX_BYTES) {
            return 'The file is larger than 2 MB.';
        }
        if ($f['error'] !== UPLOAD_ERR_OK || $f['size'] < 1 || !is_uploaded_file($f['tmp_name'])) {
            return 'The file could not be uploaded. Try again.';
        }
        // the type is read from the content, not from the name or from what the browser says
        if (!isset($types[self::mime($f['tmp_name'])])) {
            return 'The file must be ' . implode(' or ', array_map('strtoupper', $types)) . '.';
        }
        return null;
    }

    /** Stores a file that passed problem(). Returns the path for the database, or null if the disk refused. */
    public static function store(string $field, array $types, string $folder): ?string
    {
        $tmp = $_FILES[$field]['tmp_name'];
        $dir = self::root() . $folder;
        if (!is_dir($dir) && !@mkdir($dir, 0700, true) && !is_dir($dir)) {
            error_log('[MDMS] cannot create upload folder ' . $dir);
            return null;
        }
        $path = $folder . '/' . bin2hex(random_bytes(16)) . '.' . $types[self::mime($tmp)];
        return move_uploaded_file($tmp, self::root() . $path) ? $path : null;
    }

    /** The file behind a path of the database, only if it has exactly the form store() gives. */
    public static function locate(?string $path, string $folder): ?string
    {
        if ($path === null || preg_match('#\A' . preg_quote($folder, '#') . '/[a-f0-9]{32}\.(pdf|jpg|png)\z#', $path) !== 1) {
            return null;
        }
        $file = self::root() . $path;
        return is_file($file) ? $file : null;
    }

    public static function remove(?string $path, string $folder): void
    {
        $file = self::locate($path, $folder);
        if ($file !== null) {
            @unlink($file);
        }
    }

    private static function mime(string $file): string
    {
        return (string) (new \finfo(FILEINFO_MIME_TYPE))->file($file);
    }
}
