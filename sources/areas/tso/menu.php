<?php
declare(strict_types=1);
// Menu of the tso area (task B8). One entry per page; 'roles' decides who sees it.
// The page itself must still call Mdms\Auth::requireRole(...).
return [
    ['label' => 'Grid', 'href' => '/tso/', 'roles' => ['TSO']],
];
