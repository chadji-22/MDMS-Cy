<?php
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\Auth;
use Mdms\View;

Auth::requireRole('CONSUMER');
View::header('Consumer area');
?>
<p>Placeholder created by B1 (framework). The pages of this area are task <strong>B3</strong>:
add them next to this file and list them in <code>areas/consumer/menu.php</code>.</p>
<?php
View::footer();
