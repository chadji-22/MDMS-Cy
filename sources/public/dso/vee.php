<?php
/**
 * B7 · DSO / officer · Validation and estimation of a time window
 * [project.pdf §3.2 p.8-9; UC-16]   sp_RunVEE
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, Ui, Validate, View};

Auth::requireRole('DSO', 'SYSTEM_OFFICER');

$error = null;
$today = gmdate('Y-m-d');
$in = ['from' => $today . 'T00:00', 'to' => $today . 'T23:45', 'meter_id' => ''];
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    foreach ($in as $name => $_) {
        $in[$name] = Validate::post($name);
    }
    try {
        $from = Validate::dateTime($in['from']);
        $to = Validate::dateTime($in['to']);
        $meter = trim($in['meter_id']) === '' ? null : Validate::id($in['meter_id']);
        if ($from === null || $to === null) {
            throw Ui::invalid('give the first and the last slot.');
        }
        if (trim($in['meter_id']) !== '' && $meter === null) {
            throw Ui::invalid('the meter must be a whole number.');
        }
        Ui::keep('vee', ['from' => $from, 'to' => $to] + (Db::row('sp_RunVEE', [$from, $to, $meter]) ?? []));
        Ui::redirect('/dso/vee.php');
    } catch (DbError $e) {
        $error = $e;
        http_response_code($e->httpStatus());
    }
}
$done = Ui::kept('vee');

View::header('Run VEE');
if ($error) {
    View::error($error);
}
if ($done !== null): ?>
  <p class="flash <?= (int) ($done['meters_failed'] ?? 0) > 0 ? 'error' : 'ok' ?>" role="status">
    <?= View::h(Ui::ts($done['from'])) ?> – <?= View::h(Ui::ts($done['to'])) ?>: <?= (int) ($done['meters_processed'] ?? 0) ?> meters processed,
    <?= (int) ($done['meters_failed'] ?? 0) ?> failed. Readings: <?= (int) ($done['readings_valid'] ?? 0) ?> valid,
    <?= (int) ($done['readings_suspect'] ?? 0) ?> suspect, <?= (int) ($done['readings_estimated'] ?? 0) ?> estimated.
    <?php if ((int) ($done['readings_suspect'] ?? 0) > 0): ?><a href="/dso/suspects.php">Decide the suspect readings</a><?php endif; ?></p>
<?php endif; ?>
<form method="post" action="/dso/vee.php" class="card">
  <?= Csrf::field() ?>
  <label>First slot (UTC) <input type="datetime-local" step="900" name="from" value="<?= View::h($in['from']) ?>" required></label>
  <label>Last slot (UTC, included) <input type="datetime-local" step="900" name="to" value="<?= View::h($in['to']) ?>" required></label>
  <label>Only meter no. (optional) <input type="number" name="meter_id" min="1" value="<?= View::h($in['meter_id']) ?>"></label>
  <button type="submit">Run VEE</button>
</form>
<p class="muted">Only PENDING readings are checked: range of the code, register going down, spike, more than the meter type can
  carry. Gaps are filled by linear interpolation (ESTIMATED). What passes becomes VALID; the rest waits as SUSPECT.</p>
<?php
View::footer();
