<?php
declare(strict_types=1);

require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, View};

Auth::requireRole('SYSTEM_OFFICER');

$isPost = $_SERVER['REQUEST_METHOD'] === 'POST';
if ($isPost) {
    Csrf::verify();
}

$route = View::url('/staff/gdpr.php');   // full URL path (base included)
$id = filter_input(INPUT_GET, 'id', FILTER_VALIDATE_INT, ['options' => ['min_range' => 1, 'max_range' => 2147483647]]);
if ($id === false || ($isPost && $id === null)) {
    View::fail(400, 'Invalid request', 'Select a GDPR request from the list.');
}

$statuses = ['SUBMITTED', 'UNDER_REVIEW', 'PRE_APPROVED', 'APPROVED', 'REJECTED', 'EXECUTED'];
$status = filter_input(INPUT_GET, 'status');
$status = in_array($status, $statuses, true) ? $status : null;
$page = filter_input(INPUT_GET, 'page', FILTER_VALIDATE_INT, ['options' => ['min_range' => 1, 'max_range' => 1000000]]) ?: 1;
$pageSize = 25;
$error = null;
$requests = [];
try {
    $requests = $id === null
        ? Db::rows('sp_ListGdprRequests', [$status, $page, $pageSize])
        : Db::rows('sp_ListGdprRequests', [null, 1, 1, $id]);
} catch (DbError $exception) {
    $error = $exception;
}

$request = $requests[0] ?? null;
if ($id !== null && $error === null && $request === null) {
    View::fail(404, 'Request unavailable', 'The GDPR request was not found.');
}

$actions = match ($request['status'] ?? null) {
    'SUBMITTED' => ['UNDER_REVIEW' => 'Start review', 'REJECTED' => 'Reject'],
    'UNDER_REVIEW' => ['PRE_APPROVED' => 'Pre-approve', 'REJECTED' => 'Reject'],
    'PRE_APPROVED' => ['APPROVED' => 'Grant final approval', 'REJECTED' => 'Reject'],
    default => [],
};
$detailUrl = $route . '?id=' . $id;
$comment = '';

if ($isPost && $error === null) {
    $decision = filter_input(INPUT_POST, 'decision');
    if (!isset($actions[$decision])) {
        View::fail(409, 'Decision unavailable', 'Reload the request to see its current stage.');
    }
    $comment = trim((string) filter_input(INPUT_POST, 'comment'));
    if (preg_match('/\A.{0,500}\z/su', $comment) !== 1) {
        View::fail(400, 'Invalid comment', 'Use at most 500 characters for the comment.');
    }

    try {
        Db::callAsActor('sp_AdvanceGdprRequest', [$id, $decision, Db::nv($comment === '' ? null : $comment, 500)]);
        View::flash('ok', 'GDPR request updated to ' . $decision . '.');
        header('Location: ' . $detailUrl, true, 303);
        exit;
    } catch (DbError $exception) {
        $error = $exception;
        http_response_code($error->httpStatus());
    }
}

View::header($id === null ? 'GDPR review' : 'GDPR request #' . $id);
if ($error !== null) {
    View::error($error);
}
if ($id === null):
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
        <button type="submit">Filter requests</button>
    </form>
    <?php if ($requests === [] && $error === null): ?>
        <p>No matching GDPR requests.</p>
    <?php elseif ($requests !== []): ?>
        <table>
            <thead><tr><th>Request</th><th>Type</th><th>Status</th><th>Submitted (UTC)</th></tr></thead>
            <tbody>
            <?php foreach ($requests as $item): ?>
                <tr>
                    <td><a href="<?= View::h($route . '?id=' . $item['gdpr_request_id']) ?>">#<?= View::h($item['gdpr_request_id']) ?></a></td>
                    <td><?= View::h($item['request_type']) ?></td>
                    <td><?= View::h($item['status']) ?></td>
                    <td><?= View::h($item['submitted_at']) ?></td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table>
    <?php endif; ?>
    <?php if ($error === null && ($page > 1 || count($requests) === $pageSize)): ?>
        <p>
            <?php if ($page > 1): ?><a href="<?= View::h($pageUrl($page - 1)) ?>">Previous page</a><?php endif; ?>
            <?php if (count($requests) === $pageSize): ?><a href="<?= View::h($pageUrl($page + 1)) ?>">Next page</a><?php endif; ?>
        </p>
    <?php endif; ?>
<?php elseif ($request !== null): ?>
    <p><a href="<?= View::h($route) ?>">Back to GDPR review</a></p>
    <dl>
        <dt>Type</dt><dd><?= View::h($request['request_type']) ?></dd>
        <dt>Status</dt><dd><?= View::h($request['status']) ?></dd>
        <dt>Requester ID</dt><dd><?= View::h($request['user_id']) ?></dd>
        <dt>Meter ID</dt><dd><?= View::h($request['meter_id'] ?? '—') ?></dd>
        <dt>Submitted (UTC)</dt><dd><?= View::h($request['submitted_at']) ?></dd>
        <dt>Decision (UTC)</dt><dd><?= View::h($request['decided_at'] ?? '—') ?></dd>
    </dl>
    <?php if ($actions !== []): ?>
        <?php if ($request['status'] === 'PRE_APPROVED'): ?>
            <p>Final approval must come from a different officer than the pre-approval.</p>
        <?php endif; ?>
        <form method="post" action="<?= View::h($detailUrl) ?>" class="card">
            <?= Csrf::field() ?>
            <label>Comment <input name="comment" value="<?= View::h($comment) ?>" maxlength="500"></label>
            <?php foreach ($actions as $value => $label): ?>
                <button name="decision" value="<?= View::h($value) ?>"><?= View::h($label) ?></button>
            <?php endforeach; ?>
        </form>
    <?php endif; ?>
    <h2>Review history (UTC)</h2>
    <?php if ($request['history'] === null): ?>
        <p>No review history recorded.</p>
    <?php else: ?>
        <ol>
            <?php foreach (explode('; ', $request['history']) as $entry): ?>
                <li><?= View::h($entry) ?></li>
            <?php endforeach; ?>
        </ol>
    <?php endif; ?>
<?php endif; ?>
<?php View::footer(); ?>
