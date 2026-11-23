<?php
/**
 * B4 · Supplier / aggregator · Portfolio
 * [project.pdf §5.1 p.10: the customers of a supplier, the portfolio of an aggregator; UC-18]   sp_GetPortfolioSummary
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Db, Ui, View};

Auth::requireRole('SUPPLIER', 'AGGREGATOR');

$rows = Db::rows('sp_GetPortfolioSummary');
$columns = ['premises' => 'Premises', 'prosumers' => 'Prosumers', 'net_metering' => 'Net Metering',
            'net_billing' => 'Net Billing', 'meters_installed' => 'Meters installed', 'meters_active' => 'Meters active'];

View::header('Portfolio');
?>
<p class="muted">The premises whose <?= Auth::role() === 'SUPPLIER' ? 'supplier' : 'aggregator' ?> is your organization, per district.</p>
<?php if ($rows === []): ?>
  <p class="flash">No premises are linked to your organization yet.</p>
<?php else: ?>
  <div class="table-wrap"><table>
    <thead><tr><th>District</th><th class="num">Customers</th>
      <?php foreach ($columns as $label): ?><th class="num"><?= View::h($label) ?></th><?php endforeach; ?></tr></thead>
    <tbody>
    <?php foreach ($rows as $r): ?>
      <tr><td><?= View::h($r['district']) ?></td><td class="num"><?= (int) $r['customers'] ?></td>
        <?php foreach ($columns as $name => $_): ?><td class="num"><?= (int) $r[$name] ?></td><?php endforeach; ?></tr>
    <?php endforeach; ?>
    </tbody>
    <tfoot><tr><th scope="row">Total</th><td class="num">—</td>
      <?php foreach ($columns as $name => $_): ?><td class="num"><strong><?= (int) array_sum(array_column($rows, $name)) ?></strong></td><?php endforeach; ?></tr></tfoot>
  </table></div>
  <p class="muted small">A customer with premises in two districts is counted in both, so customers are not added up.</p>
<?php endif; ?>
<?php
View::footer();
