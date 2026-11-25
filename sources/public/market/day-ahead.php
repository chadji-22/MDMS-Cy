<?php
/**
 * B4 · Supplier / aggregator · Day-Ahead data (validated, final daily energy)
 * [project.pdf §5.2 p.11; UC-18]   sp_GetDayAheadAggregates; groups with fewer than 3 meters are not returned
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';
require __DIR__ . '/../../areas/market/lib.php';

use Mdms\{Auth, DbError, Ui, View};
use Mdms\Market as M;

Auth::requireRole('SUPPLIER', 'AGGREGATOR');

$error = null;
$rows = [];
$f = ['from' => Ui::get('from'), 'to' => Ui::get('to'), 'level' => Ui::get('level'), 'root' => Ui::get('root')];
try {
    $f = M\dayAheadFilters();
    $rows = M\dayAhead($f);
} catch (DbError $e) {
    $error = $e;
    http_response_code($e->httpStatus());
}
$query = http_build_query(array_filter($f, static fn($v): bool => $v !== null && $v !== ''));

View::header('Day-Ahead data');
if ($error) {
    View::error($error);
}
?>
<form method="get" action="<?= View::base() ?>/market/day-ahead.php" class="filters">
  <label>From <input type="date" name="from" value="<?= View::h($f['from']) ?>"></label>
  <label>To (inclusive) <input type="date" name="to" value="<?= View::h($f['to']) ?>"></label>
  <label>Grouping level <input type="number" class="short" name="level" min="1" max="255" value="<?= View::h($f['level']) ?>"></label>
  <label>Only under transformer no. <input type="number" class="short" name="root" min="1" value="<?= View::h($f['root']) ?>"></label>
  <button type="submit">Show</button>
</form>
<p class="muted">Validated (after VEE) and final, so the numbers do not change. Level 1 = low-voltage transformers, higher
  levels = larger areas. A group with fewer than 3 meters is not shown; try a higher level.
  <a href="<?= View::base() ?>/market/api/day-ahead.php?<?= View::h($query) ?>">Same data as JSON</a></p>
<?php if (!$error && $rows === []): ?>
  <p class="flash">No final data for this period and level.</p>
<?php elseif ($rows !== []): ?>
  <p>Import <strong><?= View::h(Ui::num(array_sum(array_column($rows, 'import_kwh')))) ?> kWh</strong> ·
    export <strong><?= View::h(Ui::num(array_sum(array_column($rows, 'export_kwh')))) ?> kWh</strong> ·
    net <strong><?= View::h(Ui::num(array_sum(array_column($rows, 'net_kwh')))) ?> kWh</strong></p>
  <div class="table-wrap"><table>
    <thead><tr><th>Day</th><th>Transformer</th><th class="num">Import (kWh)</th><th class="num">Export (kWh)</th><th class="num">Net (kWh)</th><th class="num">Meters</th></tr></thead>
    <tbody>
    <?php foreach ($rows as $r): ?>
      <tr><td class="mono"><?= View::h(substr((string) $r['day'], 0, 10)) ?></td>
        <td><?= View::h($r['transformer_name']) ?> <span class="muted small">no. <?= (int) $r['transformer_id'] ?></span></td>
        <td class="num"><?= View::h(Ui::num($r['import_kwh'])) ?></td><td class="num"><?= View::h(Ui::num($r['export_kwh'])) ?></td>
        <td class="num"><?= View::h(Ui::num($r['net_kwh'])) ?></td><td class="num"><?= (int) $r['meter_count'] ?></td></tr>
    <?php endforeach; ?>
    </tbody>
  </table></div>
<?php endif; ?>
<?php
View::footer();
