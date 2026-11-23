<?php
/**
 * B3 · Consumer · Events, consumption threshold and notification preferences
 * [project.pdf §1.2 p.5: where power-quality measurements exist the consumer is told about events such as
 *  undervoltage / overvoltage; §1.2 p.6: the consumer sets consumption thresholds and chooses how to be notified
 *  (email or SMS)]
 * Procedures: sp_GetPremiseEvents, sp_SetPremiseThreshold, sp_GetMyProfile, sp_UpdateMyProfile.
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';
require __DIR__ . '/../../areas/consumer/lib.php';

use Mdms\{Auth, Csrf, Db, DbError, View};
use Mdms\Consumer as C;

Auth::requireRole('CONSUMER');

const EVENT_LABELS = ['VOLTAGE_SAG' => 'Undervoltage (sag)', 'VOLTAGE_SWELL' => 'Overvoltage (swell)', 'THRESHOLD_EXCEEDED' => 'Threshold exceeded'];

$premiseId = C\selectedPremiseId();
$error = null;

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    $action = (string) ($_POST['action'] ?? '');
    try {
        if ($action === 'threshold') {
            $clear = isset($_POST['clear']);
            $kwh = $clear ? null : C\decimalParam('threshold_kwh');
            if (!$clear && $kwh === null) {
                throw new DbError(DbError::INPUT, 50004, 422, 'Invalid input: the threshold must be a positive number of kWh per month.');
            }
            Db::callAsActor('sp_SetPremiseThreshold', [(int) $premiseId, $kwh]);
            View::flash('ok', $clear ? 'Threshold removed.' : 'Threshold saved: ' . $kwh . ' kWh per month.');
        } elseif ($action === 'notify') {
            // sp_UpdateMyProfile also writes name, phone and IBAN: send the current values back unchanged
            $me = Db::row('sp_GetMyProfile');
            Db::callAsActor('sp_UpdateMyProfile', [
                Db::nv((string) $me['full_name'], 150), $me['phone'], $me['iban'],
                isset($_POST['notify_email']) ? 1 : 0, isset($_POST['notify_sms']) ? 1 : 0,
            ]);
            View::flash('ok', 'Notification preferences saved.');
        } else {
            throw new DbError(DbError::INPUT, 50004, 422, 'Unknown action.');
        }
        header('Location: /consumer/events.php?premise_id=' . (int) $premiseId, true, 303);
        exit;
    } catch (DbError $e) {
        $error = $e;
    }
}

$events = [];
if ($premiseId !== null) {
    try {
        $events = Db::rows('sp_GetPremiseEvents', [$premiseId, null, null]);
    } catch (DbError $e) {
        $error ??= $e;
    }
}
$premise = C\premise($premiseId);
$me = Db::row('sp_GetMyProfile');

View::header('Events and alerts');
if (C\premises() === []) {
    C\noPremiseNotice();
    View::footer();
    exit;
}
if ($error) {
    View::error($error);
}
?>
<form method="get" action="/consumer/events.php" class="filters">
  <label>Premise <select name="premise_id"><?= C\premiseOptions($premiseId) ?></select></label>
  <button type="submit">Show</button>
</form>

<div class="grid2">
  <form method="post" action="/consumer/events.php" class="card">
    <?= Csrf::field() ?>
    <input type="hidden" name="action" value="threshold">
    <input type="hidden" name="premise_id" value="<?= (int) $premiseId ?>">
    <h2>Monthly consumption threshold</h2>
    <p class="muted">When the month-to-date import of this premise passes the threshold, a
      <em>Threshold exceeded</em> event is raised (once per month) and you are notified as chosen on the right.</p>
    <label>Threshold (kWh per month)
      <input name="threshold_kwh" inputmode="decimal" placeholder="e.g. 350"
             value="<?= View::h(($premise['monthly_threshold_kwh'] ?? null) === null ? '' : C\num($premise['monthly_threshold_kwh'], 1)) ?>"></label>
    <div class="row"><button type="submit">Save threshold</button>
      <?php if (($premise['monthly_threshold_kwh'] ?? null) !== null): ?><button type="submit" name="clear" value="1" class="secondary">Remove</button><?php endif; ?></div>
  </form>

  <form method="post" action="/consumer/events.php" class="card">
    <?= Csrf::field() ?>
    <input type="hidden" name="action" value="notify">
    <input type="hidden" name="premise_id" value="<?= (int) $premiseId ?>">
    <h2>How to notify me</h2>
    <label class="check"><input type="checkbox" name="notify_email" value="1" <?= (int) ($me['notify_email'] ?? 0) === 1 ? 'checked' : '' ?>>
      Email to <?= View::h($me['email'] ?? '') ?></label>
    <label class="check"><input type="checkbox" name="notify_sms" value="1" <?= (int) ($me['notify_sms'] ?? 0) === 1 ? 'checked' : '' ?>>
      SMS to <?= View::h(($me['phone'] ?? '') !== '' ? $me['phone'] : '(no phone number in your profile)') ?></label>
    <button type="submit">Save preferences</button>
  </form>
</div>

<h2>Events of premise #<?= (int) $premiseId ?></h2>
<?php if ($events === []): ?>
  <p class="muted">No voltage or threshold events for this premise.</p>
<?php else: ?>
  <div class="table-wrap"><table>
    <thead><tr><th>Time (UTC)</th><th>Event</th><th>Severity</th><th>Description</th><th>Meter</th></tr></thead>
    <tbody>
    <?php foreach ($events as $e): ?>
      <tr><td class="mono"><?= View::h(C\ts($e['event_timestamp'])) ?></td>
        <td><?= View::h(EVENT_LABELS[$e['event_type']] ?? $e['event_type']) ?></td>
        <td><span class="badge <?= View::h(strtolower((string) $e['severity'])) ?>"><?= View::h($e['severity']) ?></span></td>
        <td><?= View::h($e['description']) ?></td><td><?= (int) $e['meter_id'] ?></td></tr>
    <?php endforeach; ?>
    </tbody>
  </table></div>
<?php endif; ?>
<?php
View::footer();
