<?php
/**
 * B3 · Consumer · 15-minute readings of a premise
 * [project.pdf §1.2 p.5: the consumer follows the 15-minute series of the meters of their premises; for prosumers
 *  (Net Billing / Net Metering) import from the grid and export from PV are shown separately;
 *  §1.2 p.6: the current month is free, earlier months need the paid service and are limited by retention]
 * Procedure: sp_GetPremiseReadings (at most 31 days per call; THROW 50008 when past data is not bought).
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';
require __DIR__ . '/../../areas/consumer/lib.php';

use Mdms\{Auth, Db, DbError, View};
use Mdms\Consumer as C;

Auth::requireRole('CONSUMER');

$premiseId = C\selectedPremiseId();
$premise = C\premise($premiseId);
$from = C\dateParam('from', C\monthStartUtc());
$to = C\dateParam('to', C\todayUtc());
$error = null;
$rows = [];

if ($premiseId !== null) {
    try {
        // 1.8.0 = active import, 2.8.0 = active export (PV); the procedure returns 2.8.0 only for prosumers
        $rows = Db::rows('sp_GetPremiseReadings', [$premiseId, C\startOf($from), C\endOf($to), Db::nv('1.8.0,2.8.0', 200)]);
    } catch (DbError $e) {
        $error = $e;
    }
}

// one line per 15-minute slot: import and export side by side
$slots = [];
$totals = ['1.8.0' => 0.0, '2.8.0' => 0.0];
foreach ($rows as $r) {
    $t = (string) $r['reading_timestamp'];
    $slots[$t] ??= ['1.8.0' => null, '2.8.0' => null, 'status' => []];
    $slots[$t][$r['obis_code']] = $r['energy'];
    $slots[$t]['status'][(string) $r['status']] = true;
    $totals[$r['obis_code']] = ($totals[$r['obis_code']] ?? 0.0) + (float) ($r['energy'] ?? 0);
}
$prosumer = C\isProsumer($premise);

View::header('15-minute readings');
if (C\premises() === []) {
    C\noPremiseNotice();
    View::footer();
    exit;
}
?>
<form method="get" action="/consumer/readings.php" class="filters">
  <label>Premise <select name="premise_id"><?= C\premiseOptions($premiseId) ?></select></label>
  <label>From <input type="date" name="from" value="<?= View::h($from) ?>"></label>
  <label>To (inclusive) <input type="date" name="to" value="<?= View::h($to) ?>"></label>
  <button type="submit">Show</button>
</form>
<p class="muted">Times are UTC. The current month (from <?= View::h(C\monthStartUtc()) ?>) is free; earlier days need
  <a href="/consumer/history.php?premise_id=<?= (int) $premiseId ?>">access to past data</a>. At most 31 days at a time.</p>

<?php if ($error): ?>
  <?php View::error($error); ?>
  <?php if ($error->category() === DbError::HISTORY): ?>
    <p class="flash">The data is hidden because the period is before the current month and access has not been bought for
      every day of it, or because it is older than the retention time of the meter.
      <a href="/consumer/history.php?premise_id=<?= (int) $premiseId ?>&amp;from=<?= View::h(substr($from, 0, 7)) ?>&amp;to=<?= View::h(substr($to, 0, 7)) ?>">See the price and buy access</a>.</p>
  <?php endif; ?>
<?php else: ?>
  <?php if ($slots === []): ?>
    <p class="flash">No readings for this premise in the period.</p>
  <?php else: ?>
    <p><strong><?= count($slots) ?></strong> slots · import <strong><?= View::h(C\num($totals['1.8.0'])) ?> kWh</strong>
      <?php if ($prosumer): ?> · export <strong><?= View::h(C\num($totals['2.8.0'])) ?> kWh</strong>
        · net <strong><?= View::h(C\num($totals['1.8.0'] - $totals['2.8.0'])) ?> kWh</strong><?php endif; ?></p>
    <div class="table-wrap"><table>
      <thead><tr><th>Slot (UTC)</th><th class="num">Import 1.8.0 (kWh)</th>
        <?php if ($prosumer): ?><th class="num">Export 2.8.0 (kWh)</th><th class="num">Net (kWh)</th><?php endif; ?>
        <th>Status</th></tr></thead>
      <tbody>
      <?php foreach ($slots as $t => $s): ?>
        <tr>
          <td class="mono"><?= View::h(C\ts($t)) ?></td>
          <td class="num"><?= View::h(C\num($s['1.8.0'])) ?></td>
          <?php if ($prosumer): ?>
            <td class="num"><?= View::h(C\num($s['2.8.0'])) ?></td>
            <td class="num"><?= $s['1.8.0'] === null && $s['2.8.0'] === null ? ''
                : View::h(C\num((float) $s['1.8.0'] - (float) $s['2.8.0'])) ?></td>
          <?php endif; ?>
          <td><?= View::h(implode(', ', array_keys($s['status']))) ?></td>
        </tr>
      <?php endforeach; ?>
      </tbody>
    </table></div>
  <?php endif; ?>
<?php endif; ?>
<?php
View::footer();
