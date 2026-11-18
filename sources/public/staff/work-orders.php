<?php
declare(strict_types=1);

require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Db, DbError, View};

Auth::requireRole('SYSTEM_ADMIN', 'SYSTEM_OFFICER');

$statuses = ['SUBMITTED', 'ASSIGNED', 'ACCEPTED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED'];
$status = filter_input(INPUT_GET, 'status');
$status = in_array($status, $statuses, true) ? $status : null;
$page = filter_input(INPUT_GET, 'page', FILTER_VALIDATE_INT, ['options' => ['min_range' => 1, 'max_range' => 1000000]]) ?: 1;
$pageSize = 25;
$orders = [];
$error = null;
try {
    $orders = Db::rows('sp_ListWorkOrders', [$status, null, null, $page, $pageSize]);
} catch (DbError $exception) {
    $error = $exception;
}

$pageLink = static fn (int $number): string => '?' . http_build_query(['status' => $status, 'page' => $number]);

View::header('Work orders');
?>
<form method="get" action="/staff/work-orders.php" class="card">
    <label>Status
        <select name="status">
            <option value="">All statuses</option>
            <?php foreach ($statuses as $option): ?>
                <option value="<?= View::h($option) ?>" <?= $status === $option ? 'selected' : '' ?>><?= View::h($option) ?></option>
            <?php endforeach; ?>
        </select>
    </label>
    <button type="submit">Filter work orders</button>
</form>
<?php if ($error !== null): ?>
    <?php View::error($error); ?>
<?php elseif ($orders === []): ?>
    <p>No matching work orders on this page.</p>
<?php else: ?>
    <table>
        <thead><tr><th>Job</th><th>Type</th><th>Status</th><th>Premise</th><th>Technician</th><th>Visit (UTC)</th></tr></thead>
        <tbody>
        <?php foreach ($orders as $order): ?>
            <tr>
                <td><a href="/staff/work-order.php?id=<?= View::h($order['work_order_id']) ?>">#<?= View::h($order['work_order_id']) ?></a></td>
                <td><?= View::h($order['work_type']) ?></td>
                <td><?= View::h($order['status']) ?></td>
                <td><?= View::h($order['premise_address'] ?? '—') ?></td>
                <td><?= View::h($order['technician_name'] ?? '—') ?></td>
                <td><?= View::h($order['scheduled_start'] ?? '—') ?></td>
            </tr>
        <?php endforeach; ?>
        </tbody>
    </table>
<?php endif; ?>
<?php if ($error === null && ($page > 1 || count($orders) === $pageSize)): ?>
    <p>
        <?php if ($page > 1): ?><a href="<?= View::h($pageLink($page - 1)) ?>">Previous page</a><?php endif; ?>
        <?php if (count($orders) === $pageSize): ?><a href="<?= View::h($pageLink($page + 1)) ?>">Next page</a><?php endif; ?>
    </p>
<?php endif; ?>
<?php View::footer(); ?>
