<?php
// Copy to config.local.php (git-ignored) when you cannot set environment variables, e.g. XAMPP on Windows.
// An environment variable of the same name always wins over this file.
return [
    'DB_HOST'   => 'mssql.cs.ucy.ac.cy',
    'DB_NAME'   => 'your_database',
    'DB_USER'   => 'your_login',
    'DB_PASS'   => 'your_password',     // never commit this
    'DB_RUN_AS' => 'mdms_php',          // see security.sql
    'APP_DEBUG' => '0',
];
