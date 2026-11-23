<?php
declare(strict_types=1);
// Menu of the tso area (tasks B8, B9). One entry per page; 'roles' decides who sees it.
// The page itself must still call Mdms\Auth::requireRole(...).
return [
    ['label' => 'Grid', 'href' => '/tso/', 'roles' => ['TSO']],
    ['label' => 'Transformer tree', 'href' => '/tso/tree.php', 'roles' => ['TSO', 'DSO', 'SYSTEM_OFFICER', 'SYSTEM_ADMIN']],
    ['label' => 'Current state', 'href' => '/tso/state.php', 'roles' => ['TSO', 'DSO']],
    ['label' => 'Frequency', 'href' => '/tso/frequency.php', 'roles' => ['TSO', 'DSO']],
    ['label' => 'Remote shedding', 'href' => '/tso/shedding.php', 'roles' => ['TSO']],
    ['label' => 'Map', 'href' => '/tso/map.php', 'roles' => ['TSO', 'DSO', 'SYSTEM_OFFICER', 'SYSTEM_ADMIN']],
];
