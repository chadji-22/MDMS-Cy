<?php
declare(strict_types=1);
// Menu of the staff area (task B6). One entry per page; 'roles' decides who sees it.
// The page itself must still call Mdms\Auth::requireRole(...).
return [
    ['label' => 'Administration', 'href' => '/staff/', 'roles' => ['SYSTEM_ADMIN', 'SYSTEM_OFFICER']],
];
