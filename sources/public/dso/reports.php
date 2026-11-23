<?php
/**
 * B7 · DSO · Network reports: voltage, phase unbalance, technical losses
 * [project.pdf §II.Γ p.3; UC-19]   sp_ReportVoltageEvents, sp_ReportPhaseUnbalance, sp_ReportTechnicalLosses
 * Showing a report is a GET. Raising the events writes to the database, so it is a POST with a token.
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, Ui, Validate, View};

Auth::requireRole('DSO');

const REPORTS = ['voltage' => 'Voltage sags and swells', 'unbalance' => 'Phase unbalance', 'losses' => 'Technical losses'];

$isPost = $_SERVER['REQUEST_METHOD'] === 'POST';
if ($isPost) {
    Csrf::verify();
}
$value = static fn(string $name): string => $isPost ? Validate::post($name) : Ui::get($name);

$report = isset(REPORTS[$value('report')]) ? $value('report') : 'voltage';
$in = [
    'transformer' => $value('transformer'),
    'from' => $value('from') !== '' ? $value('from') : gmdate('Y-m-01', strtotime(gmdate('Y-m-01') . ' -1 month')) . 'T00:00',
    'to' => $value('to') !== '' ? $value('to') : gmdate('Y-m-d', time() + 86400) . 'T00:00',
    'threshold' => $value('threshold') !== '' ? $value('threshold') : '20',
];
$tree = Db::rows('sp_GetTransformerTree', [null]);
$error = null;
$rows = null;
if ($in['transformer'] !== '') {
    try {
        $id = Validate::id($in['transformer']);
        $from = Validate::dateTime($in['from']);
        $to = Validate::dateTime($in['to']);
        $threshold = Validate::decimal($in['threshold'], 6, 2);
        if ($id === null || $from === null || $to === null || $threshold === null) {
            throw Ui::invalid('choose a transformer, a window and a threshold.');
        }
        $raise = $isPost && Validate::post('action') === 'raise' ? 1 : 0;
        $rows = match ($report) {
            'voltage' => Db::rows('sp_ReportVoltageEvents', [$id, $from, $to]),
            'unbalance' => Db::rows('sp_ReportPhaseUnbalance', [$id, $from, $to, $threshold, $raise]),
            'losses' => Db::rows('sp_ReportTechnicalLosses', [$id, $from, $to, $raise]),
        };
        if ($raise === 1 && $report !== 'voltage') {
            View::flash('ok', 'The report was run and its events were recorded.');
            Ui::redirect('/dso/reports.php?' . http_build_query(['report' => $report] + $in));
        }
    } catch (DbError $e) {
        $error = $e;
        http_response_code($e->httpStatus());
    }
}

View::header('Network reports');
if ($error) {
    View::error($error);
}
?>
<form method="get" action="/dso/reports.php" class="filters">
  <label>Report <select name="report"><?= Ui::options(REPORTS, $report) ?></select></label>
  <label>Transformer <select name="transformer" required><?= Ui::options(['' => 'Choose'] + Ui::transformerOptions($tree), $in['transformer']) ?></select></label>
  <label>From (UTC) <input type="datetime-local" name="from" value="<?= View::h($in['from']) ?>" required></label>
  <label>To (UTC, not included) <input type="datetime-local" name="to" value="<?= View::h($in['to']) ?>" required></label>
  <label>Unbalance limit (%) <input name="threshold" class="short" inputmode="decimal" value="<?= View::h($in['threshold']) ?>"></label>
  <button type="submit">Show</button>
</form>
<p class="muted">Voltage and unbalance cover every meter under the transformer. Losses need a level-1 transformer that has its own
  measurements. Allowed voltage: 207–253 V.</p>

<?php if ($rows === []): ?>
  <p class="flash ok">Nothing to report for <?= View::h(REPORTS[$report]) ?> in this window.</p>
<?php elseif ($rows !== null && $report === 'voltage'): ?>
  <div class="table-wrap"><table>
    <thead><tr><th>Transformer</th><th>Meter</th><th class="num">Sag readings</th><th class="num">Swell readings</th><th class="num">Min (V)</th><th class="num">Max (V)</th><th class="num">Sag events</th><th class="num">Swell events</th></tr></thead>
    <tbody><?php foreach ($rows as $r): ?>
      <tr><td><?= View::h($r['transformer_name']) ?></td><td><?= View::h($r['serial_number']) ?></td>
        <td class="num"><?= (int) $r['sag_readings'] ?></td><td class="num"><?= (int) $r['swell_readings'] ?></td>
        <td class="num"><?= View::h(Ui::num($r['min_voltage'], 1)) ?></td><td class="num"><?= View::h(Ui::num($r['max_voltage'], 1)) ?></td>
        <td class="num"><?= (int) $r['sag_events'] ?></td><td class="num"><?= (int) $r['swell_events'] ?></td></tr>
    <?php endforeach; ?></tbody>
  </table></div>
<?php elseif ($rows !== null && $report === 'unbalance'): ?>
  <p><?= count($rows) ?> slots above the limit<?= count($rows) > 500 ? '; the worst 500 are shown' : '' ?>.</p>
  <div class="table-wrap"><table>
    <thead><tr><th>Transformer</th><th class="num">Meter</th><th>Slot (UTC)</th><th class="num">L1 (A)</th><th class="num">L2 (A)</th><th class="num">L3 (A)</th><th class="num">Unbalance (%)</th></tr></thead>
    <tbody><?php foreach (array_slice($rows, 0, 500) as $r): ?>
      <tr><td><?= View::h($r['transformer_name']) ?></td><td class="num"><?= (int) $r['meter_id'] ?></td><td class="mono"><?= View::h(Ui::ts($r['reading_timestamp'])) ?></td>
        <td class="num"><?= View::h(Ui::num($r['current_l1'], 2)) ?></td><td class="num"><?= View::h(Ui::num($r['current_l2'], 2)) ?></td><td class="num"><?= View::h(Ui::num($r['current_l3'], 2)) ?></td>
        <td class="num"><strong><?= View::h(Ui::num($r['unbalance_pct'], 2)) ?></strong></td></tr>
    <?php endforeach; ?></tbody>
  </table></div>
<?php elseif ($rows !== null): $r = $rows[0]; ?>
  <div class="table-wrap"><table>
    <tbody>
      <tr><th scope="row">Measured at the transformer</th><td class="num"><?= View::h(Ui::num($r['input_kwh'])) ?> kWh</td></tr>
      <tr><th scope="row">Import of the meters</th><td class="num"><?= View::h(Ui::num($r['meters_import_kwh'])) ?> kWh</td></tr>
      <tr><th scope="row">Export of the meters</th><td class="num"><?= View::h(Ui::num($r['meters_export_kwh'])) ?> kWh</td></tr>
      <tr><th scope="row">Delivered (import − export)</th><td class="num"><?= View::h(Ui::num($r['delivered_kwh'])) ?> kWh</td></tr>
      <tr><th scope="row">Loss</th><td class="num"><?= View::h(Ui::num($r['loss_kwh'])) ?> kWh</td></tr>
      <tr><th scope="row">Loss (%)</th><td class="num"><?= $r['loss_pct'] === null ? 'no measurement at the transformer' : View::h(Ui::num($r['loss_pct'], 2)) . ' %' ?></td></tr>
      <tr><th scope="row">Tamper alerts in the window</th><td class="num"><?= (int) $r['tamper_alerts'] ?></td></tr>
    </tbody>
  </table></div>
  <?php if ($r['possible_theft']): ?><p class="flash error" role="alert">Loss above 8 %: possible non-technical loss (theft).</p><?php endif; ?>
<?php endif; ?>

<?php if ($rows !== null && $rows !== [] && $report !== 'voltage'): ?>
  <form method="post" action="/dso/reports.php">
    <?= Csrf::field() ?>
    <input type="hidden" name="report" value="<?= View::h($report) ?>">
    <?php foreach ($in as $name => $v): ?><input type="hidden" name="<?= View::h($name) ?>" value="<?= View::h($v) ?>"><?php endforeach; ?>
    <p><button type="submit" name="action" value="raise" class="secondary">Record events for this report</button>
      <span class="muted small">Unbalance: the worst slot of each meter, once. Losses: one event if the loss is above 8 %.</span></p>
  </form>
<?php endif; ?>
<?php
View::footer();
