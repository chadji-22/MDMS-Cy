<?php
declare(strict_types=1);
// Menu of the dso area (task B7). One entry per page; 'roles' decides who sees it.
// The page itself must still call Mdms\Auth::requireRole(...).
return [
    ['label' => 'Telemetry and VEE', 'href' => '/dso/', 'roles' => ['DSO', 'SYSTEM_OFFICER']],
    ['label' => 'Ingest packets', 'href' => '/dso/ingest.php', 'roles' => ['DSO', 'SYSTEM_OFFICER']],
    ['label' => 'Run VEE', 'href' => '/dso/vee.php', 'roles' => ['DSO', 'SYSTEM_OFFICER']],
    ['label' => 'Suspect readings', 'href' => '/dso/suspects.php', 'roles' => ['DSO', 'SYSTEM_OFFICER']],
    ['label' => 'Finalize a day', 'href' => '/dso/finalize.php', 'roles' => ['DSO', 'SYSTEM_OFFICER']],
    ['label' => 'Network reports', 'href' => '/dso/reports.php', 'roles' => ['DSO']],
    ['label' => 'Events', 'href' => '/dso/events.php', 'roles' => ['DSO', 'SYSTEM_OFFICER', 'TSO']],
];
