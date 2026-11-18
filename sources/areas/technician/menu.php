<?php
declare(strict_types=1);
// Menu of the technician area (task B5). One entry per page; 'roles' decides who sees it.
// The page itself must still call Mdms\Auth::requireRole(...).
return [
    ['label' => 'My jobs', 'href' => '/technician/', 'roles' => ['TECHNICIAN']],
];
