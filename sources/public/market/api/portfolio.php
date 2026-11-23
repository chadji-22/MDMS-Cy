<?php
declare(strict_types=1);
// B4 · JSON of /market/ (portfolio per district)
require __DIR__ . '/../../../src/bootstrap.php';

use Mdms\{Db, DbError, Ui};

Ui::jsonRole('SUPPLIER', 'AGGREGATOR');
try {
    $rows = Db::rows('sp_GetPortfolioSummary');
    Ui::json(['count' => count($rows), 'rows' => $rows]);
} catch (DbError $e) {
    Ui::json(['error' => $e->getUserMessage()], $e->httpStatus());
}
