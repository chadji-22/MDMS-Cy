<?php
declare(strict_types=1);

require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, View};

Auth::requireRole('SYSTEM_OFFICER');
$isPost = $_SERVER['REQUEST_METHOD'] === 'POST';
if ($isPost) {
    Csrf::verify();
}

$route = '/staff/remote-commands.php';
$intOptions = ['options' => ['min_range' => 1, 'max_range' => 2147483647]];
$commandId = filter_input(INPUT_GET, 'id', FILTER_VALIDATE_INT, $intOptions);
if ($commandId === false || ($isPost && $commandId === null)) {
    View::fail(400, 'Invalid command', 'Select a command from the list.');
}

$statuses = ['PENDING_APPROVAL', 'APPROVED', 'REJECTED', 'SENT', 'ACKNOWLEDGED', 'FAILED'];
$status = filter_input(INPUT_GET, 'status');
$status = in_array($status, $statuses, true) ? $status : null;
$page = filter_input(INPUT_GET, 'page', FILTER_VALIDATE_INT, ['options' => ['min_range' => 1, 'max_range' => 1000000]]) ?: 1;
$pageSize = 25;
$commands = [];
$error = null;
try {
    $commands = $commandId === null
        ? Db::rows('sp_ListCommands', [$status, null, $page, $pageSize])
        : Db::rows('sp_ListCommands', [null, null, 1, 1, $commandId]);
} catch (DbError $exception) {
    $error = $exception;
}

if ($commandId !== null && $error === null && $commands === []) {
    View::fail(404, 'Command unavailable', 'The command was not found.');
}

$command = $commands[0] ?? null;
$actions = match ($command['status'] ?? null) {
    'PENDING_APPROVAL' => ['approve' => 'Approve', 'reject' => 'Reject'],
    'APPROVED' => ['dispatch' => 'Dispatch'],
    'SENT' => ['dispatch' => 'Retry dispatch', 'ack' => 'Simulate ACK'],
    default => [],
};
$detailUrl = $route . '?id=' . $commandId;

if ($isPost && $error === null) {
    $action = filter_input(INPUT_POST, 'action');
    if (!isset($actions[$action])) {
        View::fail(409, 'Action unavailable', 'Reload the command to see its current status.');
    }

    $note = trim((string) filter_input(INPUT_POST, 'note'));
    $limit = $action === 'ack' ? 300 : 500;
    if (preg_match('/\A.{0,' . $limit . '}\z/su', $note) !== 1) {
        View::fail(400, 'Invalid note', 'Use at most ' . $limit . ' characters.');
    }

    try {
        switch ($action) {
            case 'approve':
            case 'reject':
                $decision = $action === 'approve' ? 'APPROVED' : 'REJECTED';
                Db::callAsActor('sp_DecideRemoteCommand', [$commandId, $decision, Db::nv($note === '' ? null : $note, 500)]);
                View::flash('ok', $action === 'approve' ? 'Command approved.' : 'Command rejected.');
                break;
            case 'dispatch':
                $result = Db::row('sp_DispatchCommands', [3, $commandId]);
                if (($result['attempts_sent'] ?? 0) === 1) {
                    View::flash('ok', 'Dispatch recorded. Waiting for acknowledgment.');
                } elseif (($result['commands_failed'] ?? 0) === 1) {
                    View::flash('error', 'Command marked failed after three attempts without acknowledgment.');
                } else {
                    View::flash('error', 'No dispatch was recorded. Check the current command status.');
                }
                break;
            case 'ack':
                Db::callAsActor('sp_SimulateCommandAcknowledgment', [$commandId, Db::nv($note === '' ? null : $note, 300)]);
                View::flash('ok', 'Simulated acknowledgment recorded.');
                break;
        }
        header('Location: ' . $detailUrl, true, 303);
        exit;
    } catch (DbError $exception) {
        $error = $exception;
    }
}

View::header($commandId === null ? 'Remote commands' : 'Remote command #' . $commandId);
if ($error !== null) {
    View::error($error);
}
if ($commandId === null):
    $pageUrl = static fn (int $number): string => '?' . http_build_query(['status' => $status, 'page' => $number]);
    ?>
    <form method="get" action="<?= View::h($route) ?>" class="card">
        <label>Status
            <select name="status">
                <option value="">All statuses</option>
                <?php foreach ($statuses as $option): ?>
                    <option value="<?= View::h($option) ?>" <?= $status === $option ? 'selected' : '' ?>><?= View::h($option) ?></option>
                <?php endforeach; ?>
            </select>
        </label>
        <button type="submit">Filter commands</button>
    </form>
    <?php if ($commands === [] && $error === null): ?>
        <p>No matching remote commands.</p>
    <?php elseif ($commands !== []): ?>
        <table>
            <thead><tr><th>Command</th><th>Type</th><th>Meter</th><th>Status</th><th>Attempts</th><th>Requested (UTC)</th></tr></thead>
            <tbody>
            <?php foreach ($commands as $item): ?>
                <tr>
                    <td><a href="<?= View::h($route . '?id=' . $item['command_id']) ?>">#<?= View::h($item['command_id']) ?></a></td>
                    <td><?= View::h($item['command_type']) ?></td>
                    <td><?= View::h($item['serial_number']) ?></td>
                    <td><?= View::h($item['status']) ?></td>
                    <td><?= View::h($item['attempt_count']) ?></td>
                    <td><?= View::h($item['requested_at']) ?></td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table>
    <?php endif; ?>
    <?php if ($error === null && ($page > 1 || count($commands) === $pageSize)): ?>
        <p>
            <?php if ($page > 1): ?><a href="<?= View::h($pageUrl($page - 1)) ?>">Previous page</a><?php endif; ?>
            <?php if (count($commands) === $pageSize): ?><a href="<?= View::h($pageUrl($page + 1)) ?>">Next page</a><?php endif; ?>
        </p>
    <?php endif; ?>
<?php elseif ($command !== null): ?>
    <p><a href="<?= View::h($route) ?>">Back to Remote commands</a></p>
    <dl>
        <dt>Type</dt><dd><?= View::h($command['command_type']) ?></dd>
        <dt>Meter</dt><dd><?= View::h($command['serial_number']) ?></dd>
        <dt>Status</dt><dd><?= View::h($command['status']) ?></dd>
        <dt>Parameters</dt><dd><?= View::h($command['parameters'] ?? '—') ?></dd>
        <dt>Attempts</dt><dd><?= View::h($command['attempt_count']) ?></dd>
        <dt>Last attempt (UTC)</dt><dd><?= View::h($command['last_attempt_at'] ?? '—') ?></dd>
        <dt>Acknowledged (UTC)</dt><dd><?= View::h($command['ack_at'] ?? '—') ?></dd>
        <dt>Result</dt><dd><?= View::h($command['result'] ?? '—') ?></dd>
    </dl>
    <?php if ($actions !== []): ?>
        <?php if (isset($actions['dispatch'])): ?>
            <p>Dispatch records an attempt for this command in the demo database.</p>
        <?php endif; ?>
        <form method="post" action="<?= View::h($detailUrl) ?>" class="card">
            <?= Csrf::field() ?>
            <?php if ($command['status'] !== 'APPROVED'): ?>
                <label><?= $command['status'] === 'SENT' ? 'ACK result' : 'Decision note' ?>
                    <input name="note" maxlength="<?= $command['status'] === 'SENT' ? 300 : 500 ?>">
                </label>
            <?php endif; ?>
            <?php foreach ($actions as $value => $label): ?>
                <button name="action" value="<?= View::h($value) ?>"><?= View::h($label) ?></button>
            <?php endforeach; ?>
        </form>
    <?php endif; ?>
    <h2>History</h2>
    <p><?= View::h($command['history'] ?? 'No history recorded.') ?></p>
<?php endif; ?>
<?php View::footer(); ?>
