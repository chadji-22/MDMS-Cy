<?php
/**
 * B3 · Consumer · Bills and payments
 * [project.pdf §1.3 p.6: the consumer sees the history of charges and payments; a payment keeps the link between
 *  consumer, supplier, bill and any MDMS-Cy service fee; dynamic pricing is not required]
 * Procedures: sp_GetMyBillsAndPayments (two result sets), sp_PayBill, sp_ListServiceTypes, sp_PayServiceFee.
 * Concurrency: sp_PayBill locks the bill row (UPDLOCK, HOLDLOCK), so two payments can never overpay it (§IV p.13).
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';
require __DIR__ . '/../../areas/consumer/lib.php';

use Mdms\{Auth, Csrf, Db, DbError, View};
use Mdms\Consumer as C;

Auth::requireRole('CONSUMER');

$error = null;
$services = array_values(array_filter(Db::rows('sp_ListServiceTypes'),
    static fn (array $s): bool => $s['service_name'] !== 'HISTORICAL_ACCESS'));   // bought per meter and period on history.php

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    $action = (string) ($_POST['action'] ?? '');
    $method = (string) ($_POST['method'] ?? '');
    try {
        if ($action === 'pay_bill') {
            $billId = ctype_digit((string) ($_POST['bill_id'] ?? '')) ? (int) $_POST['bill_id'] : 0;
            $amount = C\decimalParam('amount');
            if ($amount === null) {
                throw new DbError(DbError::INPUT, 50004, 422, 'Invalid input: the amount must be a positive number.');
            }
            $res = Db::rows('sp_PayBill', [$billId, $amount, $method, null]);
            View::flash('ok', sprintf('Payment #%d recorded. Bill #%d is now %s (left to pay: %s €).',
                (int) $res[0]['payment_id'], $billId, (string) $res[0]['bill_status'], C\num($res[0]['remaining'], 2)));
        } elseif ($action === 'pay_service') {
            $serviceId = ctype_digit((string) ($_POST['service_type_id'] ?? '')) ? (int) $_POST['service_type_id'] : 0;
            // the amount is the fee of the service as listed by the database, never a value typed in the browser
            $fee = null;
            foreach ($services as $s) {
                if ((int) $s['service_type_id'] === $serviceId) {
                    $fee = (string) $s['fee'];
                }
            }
            if ($fee === null) {
                throw new DbError(DbError::NOT_FOUND, 50001, 404, 'Service not found.');
            }
            $res = Db::rows('sp_PayServiceFee', [$serviceId, $fee, $method, null]);
            View::flash('ok', sprintf('Payment #%d of %s € recorded.', (int) $res[0]['payment_id'], C\num($res[0]['amount'], 2)));
        } else {
            throw new DbError(DbError::INPUT, 50004, 422, 'Unknown action.');
        }
        header('Location: /consumer/bills.php', true, 303);
        exit;
    } catch (DbError $e) {
        $error = $e;
    }
}

$sets = Db::callAsActor('sp_GetMyBillsAndPayments', [null, null]);
$bills = $sets[0] ?? [];
$payments = $sets[1] ?? [];

View::header('Bills and payments');
if ($error) {
    View::error($error);
}
?>
<h2>Bills</h2>
<?php if ($bills === []): ?>
  <p class="muted">No bills yet. Bills are issued by the supplier after a month closes.</p>
<?php else: ?>
  <div class="table-wrap"><table>
    <thead><tr><th>Bill</th><th>Period</th><th>Premise</th><th>Supplier</th><th>Tariff</th><th class="num">Amount</th><th class="num">Paid</th><th class="num">Left</th><th>Status</th><th>Due</th><th>Pay</th></tr></thead>
    <tbody>
    <?php foreach ($bills as $b): $open = in_array($b['status'], ['ISSUED', 'PARTIALLY_PAID', 'OVERDUE'], true); ?>
      <tr><td>#<?= (int) $b['bill_id'] ?></td><td class="mono"><?= View::h($b['period_start']) ?><br>– <?= View::h($b['period_end']) ?></td>
        <td>#<?= (int) $b['premise_id'] ?> <?= View::h($b['premise_address']) ?></td><td><?= View::h($b['supplier_name']) ?></td>
        <td><?= View::h($b['tariff_name']) ?> (<?= View::h(C\num($b['rate'], 4)) ?> €/kWh)</td>
        <td class="num"><?= View::h(C\num($b['amount'], 2)) ?></td><td class="num"><?= View::h(C\num($b['paid'], 2)) ?></td>
        <td class="num"><?= View::h(C\num($b['remaining'], 2)) ?></td>
        <td><span class="badge"><?= View::h($b['status']) ?></span></td><td class="mono"><?= View::h($b['due_date']) ?></td>
        <td><?php if ($open): ?>
          <form method="post" action="/consumer/bills.php" class="inline">
            <?= Csrf::field() ?>
            <input type="hidden" name="action" value="pay_bill">
            <input type="hidden" name="bill_id" value="<?= (int) $b['bill_id'] ?>">
            <input name="amount" class="short" inputmode="decimal" value="<?= View::h(number_format((float) $b['remaining'], 2, '.', '')) ?>" aria-label="Amount">
            <select name="method" aria-label="Method"><?= C\options(C\PAY_METHODS, 'CARD') ?></select>
            <button type="submit">Pay</button>
          </form>
        <?php endif; ?></td></tr>
    <?php endforeach; ?>
    </tbody>
  </table></div>
<?php endif; ?>

<h2>Pay an MDMS-Cy service fee</h2>
<?php if ($services === []): ?>
  <p class="muted">No service with a fee is offered at the moment.</p>
<?php else: ?>
  <form method="post" action="/consumer/bills.php" class="card wide">
    <?= Csrf::field() ?>
    <input type="hidden" name="action" value="pay_service">
    <div class="row">
      <label>Service <select name="service_type_id">
        <?php foreach ($services as $s): ?>
          <option value="<?= (int) $s['service_type_id'] ?>"><?= View::h($s['service_name'] . ' · ' . C\num($s['fee'], 2) . ' €') ?></option>
        <?php endforeach; ?></select></label>
      <label>Pay by <select name="method"><?= C\options(C\PAY_METHODS, 'CARD') ?></select></label>
    </div>
    <p class="muted">The amount is the fee of the service. Access to past data is bought on <a href="/consumer/history.php">its own page</a>.</p>
    <button type="submit">Pay fee</button>
  </form>
<?php endif; ?>

<h2>Payment history</h2>
<?php if ($payments === []): ?>
  <p class="muted">No payments yet.</p>
<?php else: ?>
  <div class="table-wrap"><table>
    <thead><tr><th>Payment</th><th>Date (UTC)</th><th class="num">Amount (€)</th><th>Method</th><th>Status</th><th>For</th></tr></thead>
    <tbody>
    <?php foreach ($payments as $p): ?>
      <tr><td>#<?= (int) $p['payment_id'] ?></td><td class="mono"><?= View::h(C\ts($p['payment_date'])) ?></td>
        <td class="num"><?= View::h(C\num($p['amount'], 2)) ?></td><td><?= View::h(C\PAY_METHODS[$p['method']] ?? $p['method']) ?></td>
        <td><?= View::h($p['status']) ?></td>
        <td><?php if ($p['bill_id'] !== null): ?>Bill #<?= (int) $p['bill_id'] ?>
            <?php else: ?><?= View::h($p['service_name']) ?><?php if ($p['access_meter_id'] !== null): ?>
              (meter <?= (int) $p['access_meter_id'] ?>, <?= View::h($p['access_from']) ?> – <?= View::h($p['access_to']) ?>)<?php endif; ?>
            <?php endif; ?></td></tr>
    <?php endforeach; ?>
    </tbody>
  </table></div>
<?php endif; ?>
<?php
View::footer();
