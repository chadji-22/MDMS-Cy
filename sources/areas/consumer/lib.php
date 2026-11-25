<?php
declare(strict_types=1);

/**
 * Helpers shared by the consumer pages (task B3). Outside the web root; every page includes it after bootstrap.php.
 * Nothing here talks to the database except through Mdms\Db (stored procedures only), and nothing prints a value
 * without Mdms\View::h().
 *
 * [project.pdf §1.1-§1.4 p.5-7: the consumer functions]
 */

namespace Mdms\Consumer;

use Mdms\Db;
use Mdms\View;

/** The six districts of PREMISE.CK_PREMISE_district (create.sql). */
const DISTRICTS = ['Λευκωσία', 'Λεμεσός', 'Λάρνακα', 'Πάφος', 'Αμμόχωστος', 'Κερύνεια'];
const USAGE_TYPES = ['RESIDENTIAL' => 'Residential', 'COMMERCIAL' => 'Commercial', 'INDUSTRIAL' => 'Industrial', 'AGRICULTURAL' => 'Agricultural'];
const SCHEMES = ['NONE' => 'None (consumer only)', 'NET_METERING' => 'Net Metering (prosumer)', 'NET_BILLING' => 'Net Billing (prosumer)'];
const PAY_METHODS = ['CARD' => 'Card', 'BANK_TRANSFER' => 'Bank transfer', 'DIRECT_DEBIT' => 'Direct debit', 'CASH' => 'Cash'];

/**
 * The logged-in consumer's premises, one row per premise with its meter in service (sp_ListMyPremises).
 * Called once per request.
 * @return array<int,array<string,mixed>>
 */
function premises(): array
{
    static $rows = null;
    if ($rows === null) {
        $rows = Db::rows('sp_ListMyPremises');
    }
    return $rows;
}

/** The premise with this id if it is one of the consumer's, else null (the procedures check again). */
function premise(?int $id): ?array
{
    foreach (premises() as $p) {
        if ((int) $p['premise_id'] === $id) {
            return $p;
        }
    }
    return null;
}

/** The premise id from the query string or form, defaulting to the first premise of the consumer. */
function selectedPremiseId(): ?int
{
    $raw = $_POST['premise_id'] ?? $_GET['premise_id'] ?? null;
    $id = ($raw !== null && ctype_digit((string) $raw)) ? (int) $raw : null;
    if ($id !== null) {
        return $id;                                  // the procedure decides (50002 for someone else's premise)
    }
    $all = premises();
    return $all === [] ? null : (int) $all[0]['premise_id'];
}

function isProsumer(?array $premise): bool
{
    return $premise !== null && ($premise['prosumer_scheme'] ?? 'NONE') !== 'NONE';
}

/** <option> list of the consumer's premises. */
function premiseOptions(?int $selected): string
{
    $html = '';
    foreach (premises() as $p) {
        $id = (int) $p['premise_id'];
        $html .= '<option value="' . $id . '"' . ($id === $selected ? ' selected' : '') . '>'
               . View::h('#' . $id . ' · ' . $p['address']) . '</option>';
    }
    return $html;
}

/** <option> list from a value => label map. */
function options(array $map, ?string $selected): string
{
    $html = '';
    foreach ($map as $value => $label) {
        $value = (string) $value;
        $html .= '<option value="' . View::h($value) . '"' . ($value === $selected ? ' selected' : '') . '>'
               . View::h($label) . '</option>';
    }
    return $html;
}

/** A YYYY-MM-DD value from the request, or the default when missing or not a real date. */
function dateParam(string $name, string $default): string
{
    $v = (string) ($_GET[$name] ?? $_POST[$name] ?? '');
    $d = \DateTimeImmutable::createFromFormat('!Y-m-d', $v);
    return ($d !== false && $d->format('Y-m-d') === $v) ? $v : $default;
}

/** A YYYY-MM value from the request, or the default. */
function monthParam(string $name, string $default): string
{
    $v = (string) ($_GET[$name] ?? $_POST[$name] ?? '');
    $d = \DateTimeImmutable::createFromFormat('!Y-m', $v);
    return ($d !== false && $d->format('Y-m') === $v) ? $v : $default;
}

/** Midnight of a date, as the DATETIME2(0) text the procedures take. */
function startOf(string $date): string
{
    return $date . ' 00:00:00';
}

/** Midnight of the day AFTER a date: the procedures take [from, to) and the form shows an inclusive end date. */
function endOf(string $date): string
{
    return (new \DateTimeImmutable($date))->modify('+1 day')->format('Y-m-d') . ' 00:00:00';
}

/** First day of the current month (UTC: the database decides "current month" in UTC, fn_CanViewReadings). */
function monthStartUtc(): string
{
    return gmdate('Y-m-01');
}

function todayUtc(): string
{
    return gmdate('Y-m-d');
}

/** A positive decimal from a form, or null when empty / not a number. */
function decimalParam(string $name): ?string
{
    $v = trim((string) ($_POST[$name] ?? ''));
    $v = str_replace(',', '.', $v);
    return preg_match('/^\d{1,12}(\.\d{1,4})?$/', $v) === 1 ? $v : null;
}

/** Number formatting for kWh and money (the database returns decimals as strings). */
function num(mixed $v, int $decimals = 3): string
{
    return $v === null || $v === '' ? '' : number_format((float) $v, $decimals, '.', ' ');
}

/** "2026-11-22 10:15:00" -> "2026-11-22 10:15" (times are UTC, as stored). */
function ts(mixed $v): string
{
    return $v === null ? '' : substr((string) $v, 0, 16);
}

/** The message shown when there is no premise yet. */
function noPremiseNotice(): void
{
    echo '<p class="flash">You have no premise yet. <a href="' . View::base() . '/consumer/">Add one first</a>.</p>';
}
