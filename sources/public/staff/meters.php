<?php
declare(strict_types=1);

require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Db, DbError, View};

Auth::requireRole('SYSTEM_OFFICER');

$page = filter_input(INPUT_GET, 'page', FILTER_VALIDATE_INT, ['options' => ['min_range' => 1, 'max_range' => 1000000]]) ?: 1;
$pageSize = 25;
$error = null;
try {
    $meters = Db::rows('sp_ListMeters', ['PENDING', null, null, $page, $pageSize]);
} catch (DbError $exception) {
    $error = $exception;
}

View::header('Meter approvals');
?>
<form method="get" action="/staff/meter-review.php" class="card">
    <label>Meter ID <input type="number" name="id" min="1" max="2147483647" required></label>
    <button type="submit">Open meter</button>
</form>

<h2>Pending meters</h2>
<?php
if ($error !== null) {
    View::error($error);
} elseif ($meters === []) {
    echo '<p>No pending meters on this page.</p>';
} else {
    ?>
    <table>
        <thead><tr><th>Serial number</th><th>Premise</th><th>District</th><th>Transformer</th></tr></thead>
        <tbody>
        <?php foreach ($meters as $meter): ?>
            <tr>
                <td><a href="/staff/meter-review.php?id=<?= View::h($meter['meter_id']) ?>"><?= View::h($meter['serial_number']) ?></a></td>
                <td><?= View::h($meter['premise_address']) ?></td>
                <td><?= View::h($meter['district']) ?></td>
                <td><?= View::h($meter['transformer_name']) ?></td>
            </tr>
        <?php endforeach; ?>
        </tbody>
    </table>
    <?php
}
if ($error === null && ($page > 1 || count($meters) === $pageSize)) {
    echo '<p>';
    if ($page > 1) {
        echo '<a href="?page=' . ($page - 1) . '">Previous page</a> ';
    }
    if (count($meters) === $pageSize) {
        echo '<a href="?page=' . ($page + 1) . '">Next page</a>';
    }
    echo '</p>';
}
View::footer();
