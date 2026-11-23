<?php
declare(strict_types=1);

/**
 * The questions of the market area (task B4), shared by the pages and the JSON endpoints so that both follow the same
 * rules. The organization is never a parameter: the procedures take it from the account of the logged-in user.
 * [project.pdf §II.Ε p.3-4; §5.1-§5.2 p.10-11]
 */

namespace Mdms\Market;

use Mdms\{Db, Ui, Validate};

/** @return array{from:string,to:string,level:int,root:?int} */
function dayAheadFilters(): array
{
    $from = Ui::get('from') === '' ? gmdate('Y-m-01', strtotime(gmdate('Y-m-01') . ' -1 month')) : Validate::date(Ui::get('from'));
    $to = Ui::get('to') === '' ? gmdate('Y-m-d') : Validate::date(Ui::get('to'));
    $level = Ui::get('level') === '' ? 1 : Validate::int(Ui::get('level'), 1, 255);
    $root = Ui::get('root') === '' ? null : Validate::id(Ui::get('root'));
    if ($from === null || $to === null) {
        throw Ui::invalid('from and to must be dates (YYYY-MM-DD).');
    }
    if ($level === null) {
        throw Ui::invalid('the level must be a whole number from 1 to 255.');
    }
    if (Ui::get('root') !== '' && $root === null) {
        throw Ui::invalid('the transformer must be a whole number.');
    }
    return ['from' => $from, 'to' => $to, 'level' => $level, 'root' => $root];
}

function dayAhead(array $f): array
{
    return Db::rows('sp_GetDayAheadAggregates', [$f['from'], $f['to'], $f['level'], $f['root']]);
}

/** The window is [from, to) and at most 24 hours; by default the last 24 hours. @return array{from:string,to:string,level:int} */
function intradayFilters(): array
{
    $slot = intdiv(time(), 900) * 900;
    $from = Ui::get('from') === '' ? gmdate('Y-m-d H:i:s', $slot - 86400) : Validate::dateTime(Ui::get('from'));
    $to = Ui::get('to') === '' ? gmdate('Y-m-d H:i:s', $slot) : Validate::dateTime(Ui::get('to'));
    $level = Ui::get('level') === '' ? 1 : Validate::int(Ui::get('level'), 1, 255);
    if ($from === null || $to === null) {
        throw Ui::invalid('from and to must be a date and time (YYYY-MM-DDTHH:MM).');
    }
    if ($level === null) {
        throw Ui::invalid('the level must be a whole number from 1 to 255.');
    }
    return ['from' => $from, 'to' => $to, 'level' => $level];
}

function intraday(array $f): array
{
    return Db::rows('sp_GetIntradayProvisional', [$f['from'], $f['to'], $f['level']]);
}

/** Import, export and net as numbers: the driver returns decimals as text. */
function numeric(array $rows): array
{
    foreach ($rows as &$r) {
        foreach (['import_kwh', 'export_kwh', 'net_kwh'] as $c) {
            $r[$c] = (float) $r[$c];
        }
        foreach (['transformer_id', 'meter_count'] as $c) {
            $r[$c] = (int) $r[$c];
        }
        if (array_key_exists('is_provisional', $r)) {
            $r['is_provisional'] = (bool) $r['is_provisional'];
        }
    }
    return $rows;
}
