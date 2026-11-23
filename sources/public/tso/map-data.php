<?php
declare(strict_types=1);
// B9 · JSON for the map: transformers (sp_GetTransformerTree) and meters (sp_ListMeters -> view_METER_LOCATION),
// or, with ?lat=..&lon=.., the geofences of a point (sp_FindGeofenceForPoint).
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Db, DbError, Ui, Validate};

Ui::jsonRole('TSO', 'DSO', 'SYSTEM_OFFICER', 'SYSTEM_ADMIN');

const MAX_METERS = 5000;
$number = static fn(mixed $v): ?float => $v === null ? null : (float) $v;
try {
    if (Ui::get('lat') !== '' || Ui::get('lon') !== '') {
        $lat = Validate::decimal(Ui::get('lat'), 9, 6, true);
        $lon = Validate::decimal(Ui::get('lon'), 9, 6, true);
        if ($lat === null || $lon === null || abs((float) $lat) > 90 || abs((float) $lon) > 180) {
            throw Ui::invalid('lat and lon must be coordinates.');
        }
        $path = array_map(static fn(array $r): array => ['id' => (int) $r['transformer_id'], 'name' => $r['name'], 'level' => (int) $r['level']],
            Db::rows('sp_FindGeofenceForPoint', [$lat, $lon]));
        Ui::json(['path' => $path]);
    }

    $transformers = array_map(static fn(array $t): array => [
        'id' => (int) $t['transformer_id'], 'name' => $t['name'], 'level' => (int) $t['level'], 'depth' => (int) $t['depth'],
        'capacity' => (float) $t['capacity_kva'], 'lat' => (float) $t['latitude'], 'lon' => (float) $t['longitude'],
        'box' => $t['min_lat'] === null ? null : [[(float) $t['min_lat'], (float) $t['min_lon']], [(float) $t['max_lat'], (float) $t['max_lon']]],
        'slot' => $t['reference_15_min'] === null ? null : substr((string) $t['reference_15_min'], 0, 16),
        'import' => $number($t['import_kwh']), 'export' => $number($t['export_kwh']),
        'load' => $t['import_kwh'] === null ? null : round((float) $t['import_kwh'] * 4 / (float) $t['capacity_kva'] * 100, 2),
        'meters' => (int) $t['meters_connected'],
        'reporting' => $t['meters_reporting'] === null ? null : (int) $t['meters_reporting'],
    ], Db::rows('sp_GetTransformerTree', [null]));

    // the procedure gives at most 500 rows per page
    $meters = [];
    for ($page = 1; count($meters) < MAX_METERS; $page++) {
        $rows = Db::rows('sp_ListMeters', [null, null, null, $page, 500]);
        foreach ($rows as $m) {
            if ($m['status'] !== 'REMOVED') {
                $meters[] = ['id' => (int) $m['meter_id'], 'serial' => $m['serial_number'], 'status' => $m['status'],
                             'lat' => (float) $m['latitude'], 'lon' => (float) $m['longitude'], 'transformer' => $m['transformer_name']];
            }
        }
        if (count($rows) < 500) {
            break;
        }
    }
    Ui::json(['transformers' => $transformers, 'meters' => $meters, 'complete' => count($meters) < MAX_METERS]);
} catch (DbError $e) {
    Ui::json(['error' => $e->getUserMessage()], $e->httpStatus());
}
