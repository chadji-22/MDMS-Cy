<?php
declare(strict_types=1);
// B4 · JSON of /market/day-ahead.php (same filters, same rules)
require __DIR__ . '/../../../src/bootstrap.php';
require __DIR__ . '/../../../areas/market/lib.php';

use Mdms\{DbError, Ui};
use Mdms\Market as M;

Ui::jsonRole('SUPPLIER', 'AGGREGATOR');
try {
    $f = M\dayAheadFilters();
    $rows = M\numeric(M\dayAhead($f));
    Ui::json(['filters' => $f, 'count' => count($rows), 'rows' => $rows]);
} catch (DbError $e) {
    Ui::json(['error' => $e->getUserMessage()], $e->httpStatus());
}
