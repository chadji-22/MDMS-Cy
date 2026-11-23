<?php
declare(strict_types=1);
// Menu of the consumer area (task B3). One entry per page; 'roles' decides who sees it.
// The page itself must still call Mdms\Auth::requireRole(...).   [project.pdf §1.1-§1.4 p.5-7]
return [
    ['label' => 'My premises',          'href' => '/consumer/',               'roles' => ['CONSUMER']],
    ['label' => 'Readings',             'href' => '/consumer/readings.php',   'roles' => ['CONSUMER']],
    ['label' => 'Totals',               'href' => '/consumer/aggregates.php', 'roles' => ['CONSUMER']],
    ['label' => 'Past data',            'href' => '/consumer/history.php',    'roles' => ['CONSUMER']],
    ['label' => 'Events and alerts',    'href' => '/consumer/events.php',     'roles' => ['CONSUMER']],
    ['label' => 'Requests',             'href' => '/consumer/requests.php',   'roles' => ['CONSUMER']],
    ['label' => 'Bills and payments',   'href' => '/consumer/bills.php',      'roles' => ['CONSUMER']],
    ['label' => 'Privacy (GDPR)',       'href' => '/consumer/gdpr.php',       'roles' => ['CONSUMER']],
];
