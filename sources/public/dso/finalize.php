<?php
/**
 * B7 · DSO / officer · Finalize the readings of a day and build the transformer aggregates
 * [project.pdf §3.2 p.9: after VEE the readings are immutable and the aggregates are produced; §4.2 p.10]
 * sp_FinalizeReadings, sp_BuildTransformerAggregates
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, Ui, Validate, View};

Auth::requireRole('DSO', 'SYSTEM_OFFICER');

$error = null;
$in = ['day' => gmdate('Y-m-d', time() - 86400), 'meter_id' => ''];
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    foreach ($in as $name => $_) {
        $in[$name] = Validate::post($name);
    }
    try {
        $day = Validate::date($in['day']);
        if ($day === null) {
            throw Ui::invalid('choose a day.');
        }
        if (Validate::post('action') === 'finalize') {
            $meter = trim($in['meter_id']) === '' ? null : Validate::id($in['meter_id']);
            if (trim($in['meter_id']) !== '' && $meter === null) {
                throw Ui::invalid('the meter must be a whole number.');
            }
            $rows = Db::rows('sp_FinalizeReadings', [$day, $meter]);
            $counts = array_count_values(array_column($rows, 'outcome'));
            // the finalized meters are only counted; the list shows what still needs work
            $open = array_values(array_filter($rows, static fn(array $r): bool => $r['outcome'] !== 'FINALIZED'));
            Ui::keep('finalize', ['day' => $day, 'counts' => $counts, 'open' => array_slice($open, 0, 200)]);
        } elseif (Validate::post('action') === 'build') {
            Ui::keep('build', Db::row('sp_BuildTransformerAggregates', [$day, isset($_POST['force']) ? 1 : 0]) ?? []);
        } else {
            throw Ui::invalid('unknown action.');
        }
        Ui::redirect('/dso/finalize.php');
    } catch (DbError $e) {
        $error = $e;
        http_response_code($e->httpStatus());
    }
}
$done = Ui::kept('finalize');
$built = Ui::kept('build');

View::header('Finalize a day');
if ($error) {
    View::error($error);
}
if ($done !== null): ?>
  <p class="flash <?= $done['open'] === [] ? 'ok' : 'error' ?>" role="status"><?= View::h($done['day']) ?>:
    <?= (int) ($done['counts']['FINALIZED'] ?? 0) ?> meters finalized, <?= (int) ($done['counts']['SKIPPED'] ?? 0) ?> skipped,
    <?= (int) ($done['counts']['ERROR'] ?? 0) ?> failed<?= $done['counts'] === [] ? ' (nothing left to finalize for this day)' : '' ?>.</p>
  <?php if ($done['open'] !== []): ?>
    <div class="table-wrap"><table>
      <thead><tr><th class="num">Meter</th><th>Outcome</th><th>Reason</th></tr></thead>
      <tbody><?php foreach ($done['open'] as $r): ?>
        <tr><td class="num"><?= (int) $r['meter_id'] ?></td><td><?= Ui::badge((string) $r['outcome']) ?></td><td><?= View::h($r['reason']) ?></td></tr>
      <?php endforeach; ?></tbody>
    </table></div>
    <?php if (count($done['open']) === 200): ?><p class="muted">Only the first 200 are shown.</p><?php endif; ?>
  <?php endif; ?>
<?php endif; ?>
<?php if ($built !== null): ?>
  <p class="flash ok" role="status">Transformer aggregates of <?= View::h(substr((string) ($built['day'] ?? ''), 0, 10)) ?>:
    <?= (int) ($built['quarter_hour_rows'] ?? 0) ?> quarter-hour, <?= (int) ($built['day_rows'] ?? 0) ?> day,
    <?= (int) ($built['month_rows'] ?? 0) ?> month and <?= (int) ($built['year_rows'] ?? 0) ?> year rows written.</p>
<?php endif; ?>
<div class="grid2">
  <form method="post" action="<?= View::base() ?>/dso/finalize.php" class="card">
    <?= Csrf::field() ?>
    <h2>1. Readings of the meters</h2>
    <p class="muted">A meter is finalized when it has 96 slots of 1.8.0 and no PENDING or SUSPECT reading.
      <strong>This cannot be undone:</strong> final readings and aggregates never change.</p>
    <label>Day (already ended) <input type="date" name="day" value="<?= View::h($in['day']) ?>" required></label>
    <label>Only meter no. (optional) <input type="number" name="meter_id" min="1" value="<?= View::h($in['meter_id']) ?>"></label>
    <button type="submit" name="action" value="finalize">Finalize</button>
  </form>
  <form method="post" action="<?= View::base() ?>/dso/finalize.php" class="card">
    <?= Csrf::field() ?>
    <h2>2. Aggregates of the transformers</h2>
    <p class="muted">Sums the final readings up the tree, for each 15 minutes and for the day. Also immutable.</p>
    <label>Day (already ended) <input type="date" name="day" value="<?= View::h($in['day']) ?>" required></label>
    <label class="check"><input type="checkbox" name="force" value="1"> Build even if some active meters are not final (their energy will be missing for ever)</label>
    <button type="submit" name="action" value="build">Build aggregates</button>
  </form>
</div>
<?php
View::footer();
