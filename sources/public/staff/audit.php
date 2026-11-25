<?php
declare(strict_types=1);

require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Db, DbError, View};

Auth::requireRole('SYSTEM_ADMIN', 'SYSTEM_OFFICER');

$objectType = strtoupper(trim((string) filter_input(INPUT_GET, 'object_type')));
$objectId = trim((string) filter_input(INPUT_GET, 'object_id'));
$userId = trim((string) filter_input(INPUT_GET, 'user_id'));
$from = (string) filter_input(INPUT_GET, 'from');
$to = (string) filter_input(INPUT_GET, 'to');
$page = filter_input(INPUT_GET, 'page', FILTER_VALIDATE_INT, ['options' => ['min_range' => 1, 'max_range' => 1000000]]) ?: 1;
$pageSize = 25;
$validDate = static function (string $date): bool {
    return $date === '' || (preg_match('/\A([0-9]{4})-([0-9]{2})-([0-9]{2})\z/', $date, $parts) === 1
        && checkdate((int) $parts[2], (int) $parts[3], (int) $parts[1]));
};
$user = $userId === '' ? null : filter_var($userId, FILTER_VALIDATE_INT, ['options' => ['min_range' => 1, 'max_range' => 2147483647]]);
$valid = preg_match('/\A[A-Z0-9_]{0,30}\z/', $objectType) === 1
    && preg_match('/\A[ -~]{0,30}\z/', $objectId) === 1 && $user !== false
    && $validDate($from) && $validDate($to) && ($from === '' || $to === '' || $from <= $to);
$entries = [];
$error = null;

if ($valid) {
    try {
        $entries = Db::rows('sp_GetAuditLog', [
            $objectType === '' ? null : $objectType, $objectId === '' ? null : $objectId, $user,
            $from === '' ? null : $from . 'T00:00:00', $to === '' ? null : $to . 'T23:59:59', $page, $pageSize,
        ]);
    } catch (DbError $exception) {
        $error = $exception;
    }
} else {
    http_response_code(400);
}

$filters = ['object_type' => $objectType, 'object_id' => $objectId, 'user_id' => $userId, 'from' => $from, 'to' => $to];
$pageUrl = static fn (int $number): string => '?' . http_build_query($filters + ['page' => $number]);
View::header('Audit log');
?>
<form method="get" action="<?= View::base() ?>/staff/audit.php" class="card">
    <label>Object type <input name="object_type" maxlength="30" value="<?= View::h($objectType) ?>" placeholder="e.g. WORK_ORDER"></label>
    <label>Object ID <input name="object_id" maxlength="30" value="<?= View::h($objectId) ?>"></label>
    <label>Actor user ID <input type="number" name="user_id" min="1" max="2147483647" value="<?= View::h($userId) ?>"></label>
    <label>From date (UTC) <input type="date" name="from" value="<?= View::h($from) ?>"></label>
    <label>Through date (UTC) <input type="date" name="to" value="<?= View::h($to) ?>"></label>
    <button type="submit">Filter audit log</button>
</form>
<?php if (!$valid): ?>
    <p class="flash error" role="alert">Check the object identifiers, actor ID, and date range.</p>
<?php elseif ($error !== null): ?>
    <?php View::error($error); ?>
<?php elseif ($entries === []): ?>
    <p>No audit entries match these filters.</p>
<?php else: ?>
    <table>
        <thead><tr><th>Time (UTC)</th><th>Actor</th><th>Action</th><th>Object</th><th>Change</th><th>Comment</th></tr></thead>
        <tbody>
        <?php foreach ($entries as $entry): ?>
            <tr>
                <td><?= View::h($entry['logged_at']) ?></td>
                <td><?= View::h($entry['user_name'] ?? $entry['actor_type']) ?><?php if ($entry['user_id'] !== null): ?> #<?= View::h($entry['user_id']) ?><?php endif; ?></td>
                <td><?= View::h($entry['action']) ?><br><small><?= View::h($entry['mechanism'] ?? '') ?></small></td>
                <td><?= View::h($entry['object_type']) ?> <?= View::h($entry['object_id']) ?></td>
                <td><?= View::h($entry['old_state'] ?? '—') ?> → <?= View::h($entry['new_state'] ?? '—') ?></td>
                <td><?= View::h($entry['comment'] ?? '—') ?></td>
            </tr>
        <?php endforeach; ?>
        </tbody>
    </table>
<?php endif; ?>
<?php if ($valid && $error === null && ($page > 1 || count($entries) === $pageSize)): ?>
    <p>
        <?php if ($page > 1): ?><a href="<?= View::h($pageUrl($page - 1)) ?>">Previous page</a><?php endif; ?>
        <?php if (count($entries) === $pageSize): ?><a href="<?= View::h($pageUrl($page + 1)) ?>">Next page</a><?php endif; ?>
    </p>
<?php endif; ?>
<?php View::footer(); ?>
