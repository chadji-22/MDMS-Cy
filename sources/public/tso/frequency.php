<?php
/**
 * B8 · TSO / DSO · Grid frequency: latest value per transformer, deviations, and a new measurement
 * [project.pdf §II.Δ p.3; §1.4 p.7]   sp_GetTransformerState, sp_GetEvents, sp_RecordTransformerReading
 * sp_RecordTransformerReading accepts grid equipment (no user) or a DSO. The web page never passes "no user" for a
 * person: the TSO sees the measurements and only a DSO gets the form.
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, Ui, Validate, View};

Auth::requireRole('TSO', 'DSO');

const CODES = ['14.7.0' => '14.7.0 frequency (Hz)', '1.8.0' => '1.8.0 energy of the slot (kWh)', '2.8.0' => '2.8.0 exported energy of the slot (kWh)'];

$tree = Db::rows('sp_GetTransformerTree', [null]);
$in = ['transformer_id' => '', 'slot' => gmdate('Y-m-d\TH:i', intdiv(time(), 900) * 900), 'obis_code' => '14.7.0', 'value' => ''];
$error = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    Auth::requireRole('DSO');
    foreach ($in as $name => $_) {
        $in[$name] = trim(Validate::post($name));
    }
    try {
        $id = Validate::id($in['transformer_id']);
        $slot = Validate::dateTime($in['slot']);
        $value = Validate::decimal($in['value'], 18, 4);
        if ($id === null || $slot === null || $value === null || !isset(CODES[$in['obis_code']])) {
            throw Ui::invalid('choose a transformer, a time and a code, and give a number.');
        }
        $r = Db::row('sp_RecordTransformerReading', [$id, $slot, $in['obis_code'], $value]);
        View::flash('ok', 'Measurement recorded for the slot ' . Ui::ts($r['reading_timestamp'] ?? null) . '.');
        Ui::redirect('/tso/frequency.php');
    } catch (DbError $e) {
        $error = $e;
        http_response_code($e->httpStatus());
    }
}
$rows = array_filter(Db::rows('sp_GetTransformerState', [null, null]), static fn(array $r): bool => $r['frequency_hz'] !== null);
$events = Db::rows('sp_GetEvents', ['FREQUENCY_DEVIATION', null, null, null, 1, 20]);

View::header('Grid frequency');
if ($error) {
    View::error($error);
}
?>
<p class="muted">Nominal 50 Hz; a measurement more than 0.2 Hz away raises a critical event.</p>
<?php if ($rows === []): ?>
  <p class="flash">No frequency has been measured yet.</p>
<?php else: ?>
<div class="table-wrap"><table>
  <thead><tr><th>Transformer</th><th class="num">Level</th><th class="num">Frequency (Hz)</th><th>Slot (UTC)</th><th>State</th></tr></thead>
  <tbody><?php foreach ($rows as $r): ?>
    <tr><td><?= View::h($r['name']) ?></td><td class="num"><?= (int) $r['level'] ?></td><td class="num"><?= View::h(Ui::num($r['frequency_hz'], 2)) ?></td>
      <td class="mono"><?= View::h(Ui::ts($r['frequency_at'])) ?></td><td><?= Ui::badge(abs((float) $r['frequency_hz'] - 50) > 0.2 ? 'CRITICAL' : 'OK') ?></td></tr>
  <?php endforeach; ?></tbody>
</table></div>
<?php endif; ?>
<h2>Latest deviations</h2>
<?php if ($events === []): ?>
  <p class="muted">No deviations.</p>
<?php else: ?>
<div class="table-wrap"><table>
  <thead><tr><th>Time (UTC)</th><th>Transformer</th><th>Description</th></tr></thead>
  <tbody><?php foreach ($events as $e): ?>
    <tr><td class="mono"><?= View::h(Ui::ts($e['event_timestamp'])) ?></td><td><?= View::h($e['transformer_name']) ?></td><td><?= View::h($e['description']) ?></td></tr>
  <?php endforeach; ?></tbody>
</table></div>
<?php endif; ?>

<?php if (Auth::role() === 'DSO'): ?>
<h2>Record a measurement of a transformer</h2>
<form method="post" action="/tso/frequency.php" class="card">
  <?= Csrf::field() ?>
  <label>Transformer <select name="transformer_id" required><?= Ui::options(['' => 'Choose'] + Ui::transformerOptions($tree), $in['transformer_id']) ?></select></label>
  <label>Code <select name="obis_code"><?= Ui::options(CODES, $in['obis_code']) ?></select></label>
  <label>Slot (UTC) <input type="datetime-local" step="900" name="slot" value="<?= View::h($in['slot']) ?>" required></label>
  <label>Value <input name="value" inputmode="decimal" value="<?= View::h($in['value']) ?>" required></label>
  <button type="submit">Record</button>
</form>
<?php endif; ?>
<?php
View::footer();
