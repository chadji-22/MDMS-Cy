<?php
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\Auth;
use Mdms\View;

Auth::requireRole('SYSTEM_ADMIN', 'SYSTEM_OFFICER');
View::header('Officer / admin area');
?>
<p>Placeholder created by B1 (framework). The pages of this area are task <strong>B6</strong>:
add them next to this file and list them in <code>areas/staff/menu.php</code>.</p>
<?php
View::footer();
