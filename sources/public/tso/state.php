<?php
/**
 * B8 · TSO / DSO · Current state and load of the transformers
 * [project.pdf §II.Δ p.3; §4.2 p.10; UC-17]   sp_GetTransformerState
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Db, Ui, Validate, View};

Auth::requireRole('TSO', 'DSO');

$tree = Db::rows('sp_GetTransformerTree', [null]);
$root = Validate::id(Ui::get('root'));
$level = Validate::int(Ui::get('level'), 1, 255);
$rows = Db::rows('sp_GetTransformerState', [$root, $level]);

View::header('Current state');
?>
<form method="get" action="/tso/state.php" class="filters">
  <label>Under <select name="root"><?= Ui::options(['' => 'All transformers'] + Ui::transformerOptions($tree), $root) ?></select></label>
  <label>Level <input type="number" class="short" name="level" min="1" max="255" value="<?= View::h($level) ?>"></label>
  <button type="submit">Show</button>
</form>
<?php if ($rows === []): ?>
  <p class="flash">No transformer matches.</p>
<?php else: ?>
<div class="table-wrap"><table>
  <thead><tr><th class="num">Level</th><th>Transformer</th><th>Slot (UTC)</th><th class="num">Import (kWh)</th><th class="num">Export (kWh)</th><th class="num">Meters</th><th class="num">Load (%)</th><th class="num">Frequency (Hz)</th><th>Computed (UTC)</th></tr></thead>
  <tbody><?php foreach ($rows as $r): ?>
    <tr><td class="num"><?= (int) $r['level'] ?></td><td><?= View::h($r['name']) ?></td><td class="mono"><?= View::h(Ui::ts($r['reference_15_min'])) ?></td>
      <td class="num"><?= View::h(Ui::num($r['import_kwh'])) ?></td><td class="num"><?= View::h(Ui::num($r['export_kwh'])) ?></td>
      <td class="num"><?= $r['meter_count'] === null ? '—' : (int) $r['meter_count'] ?></td><td class="num"><?= View::h(Ui::num($r['load_pct'], 2)) ?></td>
      <td class="num"><?= View::h(Ui::num($r['frequency_hz'], 2)) ?></td><td class="mono"><?= View::h(Ui::ts($r['computed_at'])) ?></td></tr>
  <?php endforeach; ?></tbody>
</table></div>
<p class="muted">Sums of 1.8.0 and 2.8.0 of the verified readings of one slot; meters without a reading are left out.
  The state is stored: it changes when it is refreshed.</p>
<?php endif; ?>
<?php
View::footer();
