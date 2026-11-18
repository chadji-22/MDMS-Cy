<?php
declare(strict_types=1);

require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Db, DbError, View};

Auth::requireRole('SYSTEM_OFFICER');

$page = filter_input(INPUT_GET, 'page', FILTER_VALIDATE_INT, ['options' => ['min_range' => 1, 'max_range' => 1000000]]) ?: 1;
$pageSize = 25;
$error = null;
$technicians = [];
try {
    $technicians = Db::rows('sp_ListPendingTechnicians', [$page, $pageSize]);
} catch (DbError $exception) {
    $error = $exception;
}

View::header('Technician approvals');
?>
<form method="get" action="/staff/technician-review.php" class="card">
    <label>Technician ID <input type="number" name="id" min="1" max="2147483647" required></label>
    <button type="submit">Open technician</button>
</form>

<h2>Pending technicians</h2>
<?php if ($error !== null): ?>
    <?php View::error($error); ?>
<?php elseif ($technicians === []): ?>
    <p>No pending technicians on this page.</p>
<?php else: ?>
    <table>
        <thead><tr><th>Technician</th><th>Specialty</th><th>Pending documents</th><th>Approved</th><th>Rejected</th></tr></thead>
        <tbody>
        <?php foreach ($technicians as $technician): ?>
            <tr>
                <td><a href="/staff/technician-review.php?id=<?= View::h($technician['user_id']) ?>"><?= View::h($technician['full_name']) ?></a></td>
                <td><?= View::h($technician['specialty']) ?></td>
                <td><?= View::h($technician['documents_pending']) ?></td>
                <td><?= View::h($technician['documents_approved']) ?></td>
                <td><?= View::h($technician['documents_rejected']) ?></td>
            </tr>
        <?php endforeach; ?>
        </tbody>
    </table>
<?php endif; ?>
<?php if ($error === null && ($page > 1 || count($technicians) === $pageSize)): ?>
    <p>
        <?php if ($page > 1): ?><a href="?page=<?= $page - 1 ?>">Previous page</a><?php endif; ?>
        <?php if (count($technicians) === $pageSize): ?><a href="?page=<?= $page + 1 ?>">Next page</a><?php endif; ?>
    </p>
<?php endif; ?>
<?php View::footer(); ?>
