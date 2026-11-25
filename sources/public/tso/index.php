<?php
/**
 * B8 · TSO · Overall picture of the grid at a 15-minute slot
 * [project.pdf §II.Δ p.3; §4.2 p.10; UC-17]   sp_GetGridOverview, sp_RefreshTransformerState (the manual trigger)
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, Ui, Validate, View};

Auth::requireRole('TSO');

$error = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    try {
        $raw = Validate::post('slot');
        $slot = $raw === '' ? null : Validate::dateTime($raw);
        if ($raw !== '' && $slot === null) {
            throw Ui::invalid('the slot must be a date and time.');
        }
        $r = Db::row('sp_RefreshTransformerState', [$slot]);
        View::flash('ok', 'The state of every transformer was computed for ' . Ui::ts($r['reference_15_min'] ?? null)
            . ' (' . (int) ($r['rows_written'] ?? 0) . ' rows).');
        Ui::redirect('/tso/');
    } catch (DbError $e) {
        $error = $e;
        http_response_code($e->httpStatus());
    }
}
$slot = Ui::get('slot') === '' ? null : Validate::dateTime(Ui::get('slot'));
$rows = Db::rows('sp_GetGridOverview', [$slot]);
$overloaded = count(array_filter($rows, static fn(array $r): bool => (bool) $r['overloaded']));
$critical = array_sum(array_column($rows, 'critical_events_24h'));
$reference = max([''] + array_map('strval', array_column($rows, 'reference_15_min')));
// the totals of the grid are the roots of the tree
$roots = array_filter($rows, static fn(array $r): bool => $r['parent_transformer_id'] === null);

View::header('Grid overview');
if ($error) {
    View::error($error);
}
?>
<div class="grid2">
  <p class="card"><span class="muted">Slot (UTC)</span><strong><?= View::h($reference === '' ? 'not computed' : Ui::ts($reference)) ?></strong></p>
  <p class="card"><span class="muted">Import / export of the grid</span><strong><?= View::h(Ui::num(array_sum(array_column($roots, 'import_kwh')))) ?> / <?= View::h(Ui::num(array_sum(array_column($roots, 'export_kwh')))) ?> kWh</strong></p>
  <p class="card"><span class="muted">Overloaded transformers</span><strong><?= $overloaded ?></strong></p>
  <p class="card"><span class="muted">Critical events in 24 h</span><strong><?= (int) $critical ?></strong></p>
</div>
<form method="get" action="<?= View::base() ?>/tso/" class="filters">
  <label>Show slot (UTC, empty = latest) <input type="datetime-local" step="900" name="slot" value="<?= View::h($slot === null ? '' : str_replace(' ', 'T', substr($slot, 0, 16))) ?>"></label>
  <button type="submit" class="secondary">Show</button>
</form>
<form method="post" action="<?= View::base() ?>/tso/" class="filters">
  <?= Csrf::field() ?>
  <label>Compute slot (UTC, empty = latest verified) <input type="datetime-local" step="900" name="slot"></label>
  <button type="submit">Refresh the state</button>
</form>
<?php if ($rows === []): ?>
  <p class="flash">There are no transformers yet.</p>
<?php else: ?>
<div class="table-wrap"><table>
  <thead><tr><th class="num">Level</th><th>Transformer</th><th class="num">Capacity (kVA)</th><th class="num">Import (kWh)</th><th class="num">Export (kWh)</th><th class="num">Meters</th><th class="num">Load (%)</th><th>State</th><th class="num">Frequency (Hz)</th><th class="num">Critical 24 h</th></tr></thead>
  <tbody><?php foreach ($rows as $r): ?>
    <tr><td class="num"><?= (int) $r['level'] ?></td><td><?= View::h($r['name']) ?></td><td class="num"><?= View::h(Ui::num($r['capacity_kva'], 0)) ?></td>
      <td class="num"><?= View::h(Ui::num($r['import_kwh'])) ?></td><td class="num"><?= View::h(Ui::num($r['export_kwh'])) ?></td>
      <td class="num"><?= $r['meter_count'] === null ? '—' : (int) $r['meter_count'] ?></td><td class="num"><?= View::h(Ui::num($r['load_pct'], 2)) ?></td>
      <td><?= $r['reference_15_min'] === null ? '<span class="muted">no data</span>' : Ui::badge($r['overloaded'] ? 'OVERLOADED' : 'OK') ?></td>
      <td class="num"><?= View::h(Ui::num($r['frequency_hz'], 2)) ?></td><td class="num"><?= (int) $r['critical_events_24h'] ?></td></tr>
  <?php endforeach; ?></tbody>
</table></div>
<p class="muted small">Load = energy of the 15 minutes × 4 (average kW) divided by the capacity.</p>
<?php endif; ?>
<?php
View::footer();
