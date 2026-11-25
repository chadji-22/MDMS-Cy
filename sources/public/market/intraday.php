<?php
/**
 * B4 · Supplier / aggregator · Intraday data (provisional, before VEE is complete)
 * [project.pdf §5.2 p.11; UC-18]   sp_GetIntradayProvisional; at most 24 hours, groups with fewer than 3 meters hidden
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';
require __DIR__ . '/../../areas/market/lib.php';

use Mdms\{Auth, DbError, Ui, View};
use Mdms\Market as M;

Auth::requireRole('SUPPLIER', 'AGGREGATOR');

$error = null;
$rows = [];
$f = ['from' => Ui::get('from'), 'to' => Ui::get('to'), 'level' => Ui::get('level')];
try {
    $f = M\intradayFilters();
    $rows = M\intraday($f);
} catch (DbError $e) {
    $error = $e;
    http_response_code($e->httpStatus());
}
$input = static fn(string $v): string => str_replace(' ', 'T', substr($v, 0, 16));      // value of datetime-local
$query = http_build_query(array_filter($f, static fn($v): bool => $v !== ''));

View::header('Intraday data');
if ($error) {
    View::error($error);
}
?>
<form method="get" action="<?= View::base() ?>/market/intraday.php" class="filters">
  <label>From (UTC) <input type="datetime-local" name="from" step="900" value="<?= View::h($input((string) $f['from'])) ?>"></label>
  <label>To (UTC, not included) <input type="datetime-local" name="to" step="900" value="<?= View::h($input((string) $f['to'])) ?>"></label>
  <label>Grouping level <input type="number" class="short" name="level" min="1" max="255" value="<?= View::h($f['level']) ?>"></label>
  <button type="submit">Show</button>
</form>
<p class="flash"><strong>Provisional.</strong> These figures come before validation and can still change. Suspect readings are
  left out. At most 24 hours; a group with fewer than 3 meters is not shown.
  <a href="<?= View::base() ?>/market/api/intraday.php?<?= View::h($query) ?>">Same data as JSON</a></p>
<?php if (!$error && $rows === []): ?>
  <p class="flash">No data in this window.</p>
<?php elseif ($rows !== []): ?>
  <div class="table-wrap"><table>
    <thead><tr><th>Slot (UTC)</th><th>Transformer</th><th class="num">Import (kWh)</th><th class="num">Export (kWh)</th><th class="num">Net (kWh)</th><th class="num">Meters</th><th>Provisional</th></tr></thead>
    <tbody>
    <?php foreach ($rows as $r): ?>
      <tr><td class="mono"><?= View::h(Ui::ts($r['slot'])) ?></td><td><?= View::h($r['transformer_name']) ?></td>
        <td class="num"><?= View::h(Ui::num($r['import_kwh'])) ?></td><td class="num"><?= View::h(Ui::num($r['export_kwh'])) ?></td>
        <td class="num"><?= View::h(Ui::num($r['net_kwh'])) ?></td><td class="num"><?= (int) $r['meter_count'] ?></td>
        <td><?= $r['is_provisional'] ? 'yes' : 'no' ?></td></tr>
    <?php endforeach; ?>
    </tbody>
  </table></div>
<?php endif; ?>
<?php
View::footer();
