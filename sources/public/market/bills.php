<?php
/**
 * B4 · Supplier · Bills of the own customers and the monthly bill run
 * [project.pdf §1.3 p.6; §II.Ε p.3]   sp_ListSupplierBills, sp_IssueMonthlyBills (both limited to the own organization)
 * The consumer's id is in the result but is not shown: a supplier works with premises, not with persons.
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, Ui, Validate, View};

Auth::requireRole('SUPPLIER');

const STATUSES = ['ISSUED', 'PARTIALLY_PAID', 'PAID', 'OVERDUE', 'CANCELLED'];
const SIZE = 50;

$error = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    try {
        if (preg_match('/\A(\d{4})-(0[1-9]|1[0-2])\z/', Validate::post('month'), $p) !== 1) {
            throw Ui::invalid('choose a month.');
        }
        // the organization parameter stays NULL: for a supplier the procedure uses its own
        Ui::keep('bill_run', ['month' => $p[0], 'rows' => Db::rows('sp_IssueMonthlyBills', [(int) $p[1], (int) $p[2], null])]);
        Ui::redirect('/market/bills.php');
    } catch (DbError $e) {
        $error = $e;
        http_response_code($e->httpStatus());
    }
}

$status = in_array(Ui::get('status'), STATUSES, true) ? Ui::get('status') : '';
$year = Validate::int(Ui::get('year'), 2000, 2100);
$month = Validate::int(Ui::get('month'), 1, 12);
$page = Validate::int(Ui::get('page'), 1, 100000) ?? 1;
$bills = Db::rows('sp_ListSupplierBills', [$status === '' ? null : $status, $year, $month, $page, SIZE]);
$run = Ui::kept('bill_run');

View::header('Customer bills');
if ($error) {
    View::error($error);
}
if ($run !== null):
    $billed = count(array_filter($run['rows'], static fn(array $r): bool => $r['outcome'] === 'BILLED'));
?>
  <p class="flash ok" role="status">Bill run of <?= View::h($run['month']) ?>: <?= $billed ?> issued,
    <?= count($run['rows']) - $billed ?> not issued<?= $run['rows'] === [] ? ' (every premise already has a bill for this month)' : '' ?>.</p>
  <?php if ($run['rows'] !== []): ?>
  <div class="table-wrap"><table>
    <thead><tr><th class="num">Premise</th><th>Outcome</th><th class="num">Bill</th><th class="num">kWh</th><th class="num">Amount (€)</th><th>Reason</th></tr></thead>
    <tbody>
    <?php foreach ($run['rows'] as $r): ?>
      <tr><td class="num"><?= (int) $r['premise_id'] ?></td><td><?= Ui::badge((string) $r['outcome']) ?></td>
        <td class="num"><?= $r['bill_id'] === null ? '—' : (int) $r['bill_id'] ?></td>
        <td class="num"><?= View::h(Ui::num($r['kwh'])) ?></td><td class="num"><?= View::h(Ui::num($r['amount'], 2)) ?></td>
        <td><?= View::h($r['reason']) ?></td></tr>
    <?php endforeach; ?>
    </tbody>
  </table></div>
  <?php endif; ?>
<?php endif; ?>

<form method="get" action="<?= View::base() ?>/market/bills.php" class="filters">
  <label>Status <select name="status"><?= Ui::options(['' => 'All'] + array_combine(STATUSES, STATUSES), $status) ?></select></label>
  <label>Year <input type="number" class="short" name="year" min="2000" max="2100" value="<?= View::h($year) ?>"></label>
  <label>Month <input type="number" class="short" name="month" min="1" max="12" value="<?= View::h($month) ?>"></label>
  <button type="submit">Show</button>
</form>
<?php if ($bills === []): ?>
  <p class="flash">No bills for these filters.</p>
<?php else: ?>
  <div class="table-wrap"><table>
    <thead><tr><th class="num">Bill</th><th>Issued</th><th>Due</th><th>Period</th><th class="num">Amount (€)</th><th class="num">Paid (€)</th><th class="num">Remaining (€)</th><th>Status</th><th class="num">Premise</th></tr></thead>
    <tbody>
    <?php foreach ($bills as $b): ?>
      <tr><td class="num"><?= (int) $b['bill_id'] ?></td><td class="mono"><?= View::h($b['issue_date']) ?></td><td class="mono"><?= View::h($b['due_date']) ?></td>
        <td class="mono"><?= View::h($b['period_start']) ?> – <?= View::h($b['period_end']) ?></td>
        <td class="num"><?= View::h(Ui::num($b['amount'], 2)) ?></td><td class="num"><?= View::h(Ui::num($b['paid'], 2)) ?></td>
        <td class="num"><?= View::h(Ui::num($b['remaining'], 2)) ?></td><td><?= Ui::badge((string) $b['status']) ?></td><td class="num"><?= (int) $b['premise_id'] ?></td></tr>
    <?php endforeach; ?>
    </tbody>
  </table></div>
<?php endif; ?>
<?= Ui::pager('/market/bills.php', ['status' => $status, 'year' => $year, 'month' => $month], $page, count($bills), SIZE) ?>

<h2>Issue the bills of a month</h2>
<form method="post" action="<?= View::base() ?>/market/bills.php" class="card">
  <?= Csrf::field() ?>
  <p class="muted">One bill for every premise of your organization with a final monthly total. A premise that already has a
    bill for the month is left out, so it is safe to run again.</p>
  <label>Month (already ended) <input type="month" name="month" value="<?= View::h(gmdate('Y-m', strtotime(gmdate('Y-m-01') . ' -1 month'))) ?>" required></label>
  <button type="submit">Issue bills</button>
</form>
<?php
View::footer();
