<?php
// Settings for the department web server (https://students.cs.ucy.ac.cy/~<login>/mdms/).
// deploy/install.sh copies this file to config.local.php and puts your login in BASE_PATH.
// NO password here: on that server every file PHP can read is readable by every account, so the database password is
// typed on the Connect page and kept only in the PHP session on the web server.
return [
    'DB_HOST'   => 'mssql.cs.ucy.ac.cy\SQL2025',
    'DB_NAME'   => 'ichara09',          // the team database: pre-filled on the Connect page (another one can be typed)
    'DB_USER'   => 'ichara09',          // pre-filled on the Connect page
    'DB_PASS'   => '',                  // keep EMPTY on the server
    'DB_RUN_AS' => 'mdms_php',
    'BASE_PATH' => '/~__USER__/mdms',
    'APP_DEBUG' => '0',
];
