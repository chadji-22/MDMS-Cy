<?php
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\Auth;
use Mdms\View;

Auth::requireRole('SUPPLIER', 'AGGREGATOR');
View::header('Supplier / aggregator area');
?>
<p>Placeholder created by B1 (framework). The pages of this area are task <strong>B4</strong>:
add them next to this file and list them in <code>areas/market/menu.php</code>.</p>
<?php
View::footer();
