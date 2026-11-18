<?php
declare(strict_types=1);
// Menu of the consumer area (task B3). One entry per page; 'roles' decides who sees it.
// The page itself must still call Mdms\Auth::requireRole(...).
return [
    ['label' => 'My premises and bills', 'href' => '/consumer/', 'roles' => ['CONSUMER']],
];
