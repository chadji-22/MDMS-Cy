<?php
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\Auth;
use Mdms\View;

Auth::requireRole('TECHNICIAN');
View::header('Technician area');
?>
<p>Placeholder created by B1 (framework). The pages of this area are task <strong>B5</strong>:
add them next to this file and list them in <code>areas/technician/menu.php</code>.</p>
<?php
View::footer();
