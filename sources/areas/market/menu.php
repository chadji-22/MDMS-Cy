<?php
declare(strict_types=1);
// Menu of the market area (task B4). One entry per page; 'roles' decides who sees it.
// The page itself must still call Mdms\Auth::requireRole(...).
return [
    ['label' => 'Portfolio and market data', 'href' => '/market/', 'roles' => ['SUPPLIER', 'AGGREGATOR']],
];
