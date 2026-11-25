<?php
// Copy to config.local.php (git-ignored) when you cannot set environment variables, e.g. XAMPP on Windows
// or the department web server. An environment variable of the same name always wins over this file.
return [
    'DB_HOST'   => 'mssql.cs.ucy.ac.cy\SQL2025',   // our build lives on the SQL2025 instance
    'DB_NAME'   => 'your_database',     // pre-filled on the Connect page when DB_PASS is empty
    'DB_USER'   => 'your_login',        // pre-filled on the Connect page when DB_PASS is empty
    // Leave EMPTY on the department web server: the password is then typed once per browser session on the
    // Connect page and kept only in the PHP session (a file there would be readable by every account).
    // Set it only on your own machine. Never commit it.
    'DB_PASS'   => '',
    'DB_RUN_AS' => 'mdms_php',          // see security.sql
    'BASE_PATH' => '',                  // '' when public/ is the site root; '/~your_login/mdms' on students.cs.ucy.ac.cy
    'APP_DEBUG' => '0',
];
