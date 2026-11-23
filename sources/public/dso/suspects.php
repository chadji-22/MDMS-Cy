<?php
/**
 * B7 · DSO / officer · Suspect readings: accept as they are, or edit
 * [project.pdf §3.2 p.8-9: the officer decides; editing keeps the original value and who changed it; UC-16]
 * sp_ListSuspectReadings, sp_AcceptSuspectReading, sp_EditReading (also for ESTIMATED and EDITED readings, by number)
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, Ui, Validate, View};

Auth::requireRole('DSO', 'SYSTEM_OFFICER');

const SIZE = 25;
$page = Validate::int(Ui::get('page'), 1, 100000) ?? 1;
$from = Validate::dateTime(Ui::get('from'));
$to = Validate::dateTime(Ui::get('to'));
$filters = array_filter(['from' => $from === null ? null : str_replace(' ', 'T', substr($from, 0, 16)),
                         'to' => $to === null ? null : str_replace(' ', 'T', substr($to, 0, 16))]);
$self = '/dso/suspects.php?' . http_build_query($filters + ['page' => $page]);

$error = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    try {
        $id = Validate::bigId(Validate::post('reading_id'));
        if ($id === null) {
            throw Ui::invalid('the reading number is missing.');
        }
        $note = Db::nv(Validate::note(Validate::post('note'), 300), 300);
        if (Validate::post('action') === 'accept') {
            Db::callAsActor('sp_AcceptSuspectReading', [$id, $note]);
            View::flash('ok', 'Reading ' . $id . ' was accepted as it is.');
        } elseif (Validate::post('action') === 'edit') {
            $value = Validate::decimal(Validate::post('new_value'), 18, 4, true);
            if ($value === null) {
                throw Ui::invalid('the new value must be a number with at most 4 decimals.');
            }
            Db::callAsActor('sp_EditReading', [$id, $value, $note]);
            View::flash('ok', 'Reading ' . $id . ' was changed to ' . $value . '. The original value is kept.');
        } else {
            throw Ui::invalid('unknown action.');
        }
        Ui::redirect($self);
    } catch (DbError $e) {
        $error = $e;
        http_response_code($e->httpStatus());
    }
}
$rows = Db::rows('sp_ListSuspectReadings', [$from, $to, $page, SIZE]);

View::header('Suspect readings');
if ($error) {
    View::error($error);
}
?>
<form method="get" action="/dso/suspects.php" class="filters">
  <label>From (UTC) <input type="datetime-local" name="from" value="<?= View::h($filters['from'] ?? '') ?>"></label>
  <label>To (UTC) <input type="datetime-local" name="to" value="<?= View::h($filters['to'] ?? '') ?>"></label>
  <button type="submit">Show</button>
</form>
<?php if ($rows === []): ?>
  <p class="flash ok">No suspect readings here.</p>
<?php else: ?>
  <div class="table-wrap"><table>
    <thead><tr><th class="num">Reading</th><th>Slot (UTC)</th><th>Meter</th><th>Code</th><th class="num">Before</th><th class="num">Value</th><th class="num">After</th><th class="num">Energy</th><th>Why</th><th>Decision</th></tr></thead>
    <tbody>
    <?php foreach ($rows as $r): ?>
      <tr>
        <td class="num"><?= (int) $r['reading_id'] ?></td><td class="mono"><?= View::h(Ui::ts($r['reading_timestamp'])) ?></td>
        <td><?= View::h($r['serial_number']) ?></td><td><?= View::h($r['obis_code']) ?></td>
        <td class="num"><?= View::h(Ui::num($r['previous_value'], 4)) ?></td><td class="num"><strong><?= View::h(Ui::num($r['value'], 4)) ?></strong></td>
        <td class="num"><?= View::h(Ui::num($r['next_value'], 4)) ?></td><td class="num"><?= View::h(Ui::num($r['delta_value'], 4)) ?></td>
        <td><?= Ui::badge((string) $r['vee_rule']) ?> <span class="small"><?= View::h($r['vee_note']) ?></span></td>
        <td>
          <form method="post" action="<?= View::h($self) ?>" class="inline">
            <?= Csrf::field() ?>
            <input type="hidden" name="reading_id" value="<?= (int) $r['reading_id'] ?>">
            <input name="new_value" class="short" inputmode="decimal" placeholder="new value" aria-label="New value of reading <?= (int) $r['reading_id'] ?>">
            <input name="note" maxlength="300" placeholder="note (optional)" aria-label="Note for reading <?= (int) $r['reading_id'] ?>">
            <button type="submit" name="action" value="edit">Edit</button>
            <button type="submit" name="action" value="accept" class="secondary">Accept as is</button>
          </form>
        </td>
      </tr>
    <?php endforeach; ?>
    </tbody>
  </table></div>
<?php endif; ?>
<?= Ui::pager('/dso/suspects.php', $filters, $page, count($rows), SIZE) ?>

<h2>Edit an estimated or already edited reading</h2>
<form method="post" action="<?= View::h($self) ?>" class="card">
  <?= Csrf::field() ?>
  <input type="hidden" name="action" value="edit">
  <label>Reading no. <input type="number" name="reading_id" min="1" required></label>
  <label>New value <input name="new_value" inputmode="decimal" required></label>
  <label>Note (optional) <input name="note" maxlength="300"></label>
  <button type="submit">Edit</button>
</form>
<p class="muted">A final reading cannot be changed. The energy of the slot and of the next one is computed again.</p>
<?php
View::footer();
