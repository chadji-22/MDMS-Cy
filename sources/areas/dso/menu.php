<?php
declare(strict_types=1);
// Menu of the dso area (task B7). One entry per page; 'roles' decides who sees it.
// The page itself must still call Mdms\Auth::requireRole(...).
return [
    ['label' => 'Telemetry and VEE', 'href' => '/dso/', 'roles' => ['DSO', 'SYSTEM_OFFICER']],
];
