<?php
declare(strict_types=1);
header('Location: home.php', true, 303);   // relative: works at the site root and in a sub-folder (BASE_PATH)
exit;
