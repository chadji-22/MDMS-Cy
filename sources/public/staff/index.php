<?php
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\Auth;
use Mdms\View;

Auth::requireRole('SYSTEM_ADMIN', 'SYSTEM_OFFICER');
View::header('Officer / admin area');
?>
<ul class="cards">
    <li><a href="/staff/work-orders.php">Work orders</a></li>
    <li><a href="/staff/accounts.php">Accounts and organizations</a></li>
    <li><a href="/staff/audit.php">Audit log</a></li>
    <li><a href="/staff/statistics.php">Statistics</a></li>
    <?php if (Auth::role() === 'SYSTEM_OFFICER'): ?>
        <li><a href="/staff/meters.php">Meter approvals</a></li>
        <li><a href="/staff/technicians.php">Technician approvals</a></li>
        <li><a href="/staff/remote-commands.php">Remote commands</a></li>
        <li><a href="/staff/gdpr.php">GDPR review</a></li>
        <li><a href="/staff/catalogs.php">Catalogs</a></li>
    <?php endif; ?>
</ul>
<?php
View::footer();
