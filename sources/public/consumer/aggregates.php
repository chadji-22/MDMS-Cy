<?php
/**
 * B3 · Consumer · Daily, monthly and yearly totals (aggregates) of a premise
 * [project.pdf §1.2 p.6: historical and summary views use daily, monthly and yearly aggregates, so the history is not
 *  recomputed from the raw readings; the access and retention rules stay the same as for the readings]
 * Procedure: sp_GetPremiseAggregates (final aggregates only; THROW 50008 when past data is not bought).
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';
require __DIR__ . '/../../areas/consumer/lib.php';

use Mdms\{Auth, Db, DbError, View};
use Mdms\Consumer as C;

Auth::requireRole('CONSUMER');

const PERIODS = ['DAY' => 'Daily', 'MONTH' => 'Monthly', 'YEAR' => 'Yearly'];
const OBIS_LABELS = ['1.8.0' => 'Import 1.8.0', '1.8.1' => 'Import day 1.8.1', '1.8.2' => 'Import night 1.8.2', '2.8.0' => 'Export 2.8.0 (PV)'];

$premiseId = C\selectedPremiseId();
$period = (string) ($_GET['period'] ?? 'DAY');
if (!isset(PERIODS[$period])) {
    $period = 'DAY';
}
// default windows: this month by day, this year by month, the last five years by year
$defaults = ['DAY' => [C\monthStartUtc(), C\todayUtc()], 'MONTH' => [gmdate('Y-01-01'), C\todayUtc()],
             'YEAR' => [(string) ((int) gmdate('Y') - 4) . '-01-01', C\todayUtc()]];
$from = C\dateParam('from', $defaults[$period][0]);
$to = C\dateParam('to', $defaults[$period][1]);
$error = null;
$rows = [];

if ($premiseId !== null) {
    try {
        $rows = Db::rows('sp_GetPremiseAggregates', [$premiseId, $period, C\startOf($from), C\endOf($to)]);
    } catch (DbError $e) {
        $error = $e;
    }
}

// pivot: one line per period, one column per OBIS code present
$table = [];
$codes = [];
foreach ($rows as $r) {
    $table[(string) $r['period_start']][(string) $r['obis_code']] = $r['value'];
    $codes[(string) $r['obis_code']] = true;
}
ksort($codes);
$codes = array_keys($codes);
$fmt = ['DAY' => 10, 'MONTH' => 7, 'YEAR' => 4][$period];

View::header('Totals by day, month and year');
if (C\premises() === []) {
    C\noPremiseNotice();
    View::footer();
    exit;
}
?>
<form method="get" action="/consumer/aggregates.php" class="filters">
  <label>Premise <select name="premise_id"><?= C\premiseOptions($premiseId) ?></select></label>
  <label>Period <select name="period"><?= C\options(PERIODS, $period) ?></select></label>
  <label>From <input type="date" name="from" value="<?= View::h($from) ?>"></label>
  <label>To (inclusive) <input type="date" name="to" value="<?= View::h($to) ?>"></label>
  <button type="submit">Show</button>
</form>
<p class="muted">Only final totals are shown (after validation, VEE). A period that starts before the current month needs
  <a href="/consumer/history.php?premise_id=<?= (int) $premiseId ?>">access to past data</a>, exactly like the readings.</p>

<?php if ($error): ?>
  <?php View::error($error); ?>
  <?php if ($error->category() === DbError::HISTORY): ?>
    <p class="flash">The totals are hidden because the period reaches before the current month and access has not been
      bought for every day of it, or because it is older than the retention time.
      <a href="/consumer/history.php?premise_id=<?= (int) $premiseId ?>&amp;from=<?= View::h(substr($from, 0, 7)) ?>&amp;to=<?= View::h(substr($to, 0, 7)) ?>">See the price and buy access</a>.</p>
  <?php endif; ?>
<?php elseif ($table === []): ?>
  <p class="flash">No final totals for this premise in the period (totals appear after the readings are finalized).</p>
<?php else: ?>
  <div class="table-wrap"><table>
    <thead><tr><th><?= View::h(PERIODS[$period]) ?></th>
      <?php foreach ($codes as $c): ?><th class="num"><?= View::h(OBIS_LABELS[$c] ?? $c) ?> (kWh)</th><?php endforeach; ?></tr></thead>
    <tbody>
    <?php foreach ($table as $start => $vals): ?>
      <tr><td class="mono"><?= View::h(substr($start, 0, $fmt)) ?></td>
        <?php foreach ($codes as $c): ?><td class="num"><?= View::h(C\num($vals[$c] ?? null)) ?></td><?php endforeach; ?></tr>
    <?php endforeach; ?>
    </tbody>
  </table></div>
<?php endif; ?>
<?php
View::footer();
