<?php
/**
 * B3 · Consumer · Access to past data (earlier months)
 * [project.pdf §1.2 p.6: the current month is free; data of earlier months needs an extra charge; what can be bought is
 *  limited by the retention period of the consumer's data (3 years, or 1 month after an approved GDPR request, §1.4 p.6-7)]
 * Procedures: sp_GetHistoricalAccessQuote, sp_BuyHistoricalAccess, sp_GetMyBillsAndPayments (the purchases made).
 * The access rule itself is fn_CanViewReadings, applied inside sp_GetPremiseReadings / sp_GetPremiseAggregates.
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';
require __DIR__ . '/../../areas/consumer/lib.php';

use Mdms\{Auth, Csrf, Db, DbError, View};
use Mdms\Consumer as C;

Auth::requireRole('CONSUMER');

$premiseId = C\selectedPremiseId();
$premise = C\premise($premiseId);
$meterId = $premise['meter_id'] ?? null;
$lastMonth = gmdate('Y-m', strtotime(C\monthStartUtc() . ' -1 month'));
$fromMonth = C\monthParam('from', $lastMonth);
$toMonth = C\monthParam('to', $fromMonth);
$accessFrom = $fromMonth . '-01';
$accessTo = (new DateTimeImmutable($toMonth . '-01'))->modify('last day of this month')->format('Y-m-d');
$method = (string) ($_POST['method'] ?? 'CARD');
$error = null;
$quote = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    try {
        if ($meterId === null) {
            throw new DbError(DbError::INPUT, 50004, 422, 'This premise has no meter in service, so there is no data to buy.');
        }
        $res = Db::rows('sp_BuyHistoricalAccess', [(int) $meterId, $accessFrom, $accessTo, $method, null]);
        View::flash('ok', sprintf('Access to %s – %s bought for %s €. The readings and totals of that period are now visible.',
            $accessFrom, $accessTo, C\num($res[0]['amount'] ?? null, 2)));
        header('Location: /consumer/readings.php?premise_id=' . (int) $premiseId . '&from=' . $accessFrom . '&to='
            . min($accessTo, (new DateTimeImmutable($accessFrom))->modify('+30 days')->format('Y-m-d')), true, 303);
        exit;
    } catch (DbError $e) {
        $error = $e;
    }
}

if ($meterId !== null) {
    try {
        $quote = Db::row('sp_GetHistoricalAccessQuote', [(int) $meterId, $accessFrom, $accessTo]);
    } catch (DbError $e) {
        $error ??= $e;
    }
}

// what has been bought already (second result set of sp_GetMyBillsAndPayments)
$sets = Db::callAsActor('sp_GetMyBillsAndPayments', [null, null]);
$bought = array_values(array_filter($sets[1] ?? [], static fn (array $p): bool => $p['access_meter_id'] !== null));

View::header('Access to past data');
if (C\premises() === []) {
    C\noPremiseNotice();
    View::footer();
    exit;
}
if ($error) {
    View::error($error);
}
?>
<p>The readings of the <strong>current month</strong> are free. Earlier months are a paid service, per meter and per
  month, and only for data the system still keeps: raw 15-minute readings are kept 3 years, or 1 month after an approved
  request to reduce retention.</p>

<form method="get" action="/consumer/history.php" class="filters">
  <label>Premise <select name="premise_id"><?= C\premiseOptions($premiseId) ?></select></label>
  <label>From month <input type="month" name="from" value="<?= View::h($fromMonth) ?>"></label>
  <label>To month <input type="month" name="to" value="<?= View::h($toMonth) ?>"></label>
  <button type="submit">Get the price</button>
</form>

<?php if ($meterId === null): ?>
  <p class="flash">This premise has no meter in service yet, so there is no data to buy.</p>
<?php elseif ($quote !== null): ?>
  <div class="card wide">
    <p>Meter <strong><?= View::h($premise['serial_number']) ?></strong> · period <strong><?= View::h($quote['access_from']) ?></strong>
      to <strong><?= View::h($quote['access_to']) ?></strong> · <?= (int) $quote['months'] ?> month(s) ×
      <?= View::h(C\num($quote['fee_per_month'], 2)) ?> € = <strong><?= View::h(C\num($quote['amount'], 2)) ?> €</strong></p>
    <p class="muted">Oldest date still kept for this meter: <?= View::h($quote['earliest_date_kept']) ?>.</p>
    <?php if ((int) $quote['can_buy'] === 1): ?>
      <form method="post" action="/consumer/history.php" class="row">
        <?= Csrf::field() ?>
        <input type="hidden" name="premise_id" value="<?= (int) $premiseId ?>">
        <input type="hidden" name="from" value="<?= View::h($fromMonth) ?>">
        <input type="hidden" name="to" value="<?= View::h($toMonth) ?>">
        <label>Pay by <select name="method"><?= C\options(C\PAY_METHODS, $method) ?></select></label>
        <button type="submit">Buy access for <?= View::h(C\num($quote['amount'], 2)) ?> €</button>
      </form>
    <?php else: ?>
      <p class="flash error">This period cannot be bought: it must end before the current month
        (<?= View::h(C\monthStartUtc()) ?>) and start on or after <?= View::h($quote['earliest_date_kept']) ?>.</p>
    <?php endif; ?>
  </div>
<?php endif; ?>

<h2>Access bought</h2>
<?php if ($bought === []): ?>
  <p class="muted">None yet.</p>
<?php else: ?>
  <div class="table-wrap"><table>
    <thead><tr><th>Payment</th><th>Date</th><th>Meter</th><th>Period</th><th class="num">Amount (€)</th><th>Status</th></tr></thead>
    <tbody>
    <?php foreach ($bought as $b): ?>
      <tr><td>#<?= (int) $b['payment_id'] ?></td><td><?= View::h(C\ts($b['payment_date'])) ?></td><td><?= (int) $b['access_meter_id'] ?></td>
        <td><?= View::h($b['access_from']) ?> – <?= View::h($b['access_to']) ?></td>
        <td class="num"><?= View::h(C\num($b['amount'], 2)) ?></td><td><?= View::h($b['status']) ?></td></tr>
    <?php endforeach; ?>
    </tbody>
  </table></div>
<?php endif; ?>
<?php
View::footer();
