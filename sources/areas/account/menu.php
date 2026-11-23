<?php
declare(strict_types=1);
// Menu of the account area (task B2). One entry per page; 'roles' decides who sees it.
// The page itself must still call Mdms\Auth::requireLogin() / requireRole(...).
return [
    ['label' => 'My profile', 'href' => '/account/profile.php', 'roles' => Mdms\Auth::ROLES],
    ['label' => 'My documents', 'href' => '/account/documents.php', 'roles' => ['TECHNICIAN']],
];
