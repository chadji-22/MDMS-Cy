<?php
declare(strict_types=1);
// Menu of the staff area (task B6). One entry per page; 'roles' decides who sees it.
// The page itself must still call Mdms\Auth::requireRole(...).
return [
    ['label' => 'Administration', 'href' => '/staff/', 'roles' => ['SYSTEM_ADMIN', 'SYSTEM_OFFICER']],
    ['label' => 'Meter approvals', 'href' => '/staff/meters.php', 'roles' => ['SYSTEM_OFFICER']],
    ['label' => 'Technician approvals', 'href' => '/staff/technicians.php', 'roles' => ['SYSTEM_OFFICER']],
    ['label' => 'Work orders', 'href' => '/staff/work-orders.php', 'roles' => ['SYSTEM_ADMIN', 'SYSTEM_OFFICER']],
    ['label' => 'Remote commands', 'href' => '/staff/remote-commands.php', 'roles' => ['SYSTEM_OFFICER']],
    ['label' => 'GDPR review', 'href' => '/staff/gdpr.php', 'roles' => ['SYSTEM_OFFICER']],
    ['label' => 'Catalogs', 'href' => '/staff/catalogs.php', 'roles' => ['SYSTEM_OFFICER']],
    ['label' => 'Accounts and organizations', 'href' => '/staff/accounts.php', 'roles' => ['SYSTEM_ADMIN', 'SYSTEM_OFFICER']],
    ['label' => 'Audit log', 'href' => '/staff/audit.php', 'roles' => ['SYSTEM_ADMIN', 'SYSTEM_OFFICER']],
    ['label' => 'Statistics', 'href' => '/staff/statistics.php', 'roles' => ['SYSTEM_ADMIN', 'SYSTEM_OFFICER']],
];
