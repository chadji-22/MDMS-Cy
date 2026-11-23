<?php
declare(strict_types=1);
// Menu of the market area (task B4). One entry per page; 'roles' decides who sees it.
// The page itself must still call Mdms\Auth::requireRole(...).
return [
    ['label' => 'Portfolio', 'href' => '/market/', 'roles' => ['SUPPLIER', 'AGGREGATOR']],
    ['label' => 'Day-Ahead', 'href' => '/market/day-ahead.php', 'roles' => ['SUPPLIER', 'AGGREGATOR']],
    ['label' => 'Intraday', 'href' => '/market/intraday.php', 'roles' => ['SUPPLIER', 'AGGREGATOR']],
    ['label' => 'Customer bills', 'href' => '/market/bills.php', 'roles' => ['SUPPLIER']],
    ['label' => 'Data for other systems', 'href' => '/market/data.php', 'roles' => ['SUPPLIER', 'AGGREGATOR']],
];
