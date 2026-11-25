<?php
declare(strict_types=1);

require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Db, DbError, View};

Auth::requireRole('TECHNICIAN');

$jobId = filter_input(INPUT_GET, 'id', FILTER_VALIDATE_INT, [
    'options' => ['min_range' => 1, 'max_range' => 2147483647],
]);
if ($jobId === false || $jobId === null) {
    View::fail(400, 'Invalid job', 'Select a job from My Jobs.');
}

try {
    $history = Db::rows('sp_GetWorkOrderHistory', [$jobId]);
} catch (DbError $error) {
    View::fail($error->httpStatus(), 'Job unavailable', $error->getUserMessage());
}

if ($history === []) {
    View::fail(404, 'Job unavailable', 'The job could not be found.');
}

$job = $history[0];
View::header('Job #' . $jobId);
?>
<p><a href="<?= View::base() ?>/technician/">Back to My Jobs</a></p>
<dl>
    <dt>Type</dt><dd><?= View::h($job['work_type']) ?></dd>
    <dt>Status</dt><dd><?= View::h($job['current_status']) ?></dd>
    <dt>Description</dt><dd><?= View::h($job['description'] ?? '—') ?></dd>
    <dt>Visit (UTC)</dt>
    <dd><?= View::h($job['scheduled_start'] ?? '—') ?><?php if ($job['scheduled_end'] !== null): ?> to <?= View::h($job['scheduled_end']) ?><?php endif; ?></dd>
    <?php if ($job['completed_at'] !== null): ?>
        <dt>Completed (UTC)</dt><dd><?= View::h($job['completed_at']) ?></dd>
        <dt>Findings</dt><dd><?= View::h($job['findings'] ?? '—') ?></dd>
    <?php endif; ?>
</dl>
<h2>History</h2>
<?php if ($history[0]['logged_at'] === null): ?>
    <p>No history recorded for this job.</p>
<?php else: ?>
    <table>
        <thead><tr><th>Time (UTC)</th><th>Action</th><th>Previous state</th><th>New state</th><th>Comment</th></tr></thead>
        <tbody>
        <?php foreach ($history as $event): ?>
            <tr>
                <td><?= View::h($event['logged_at']) ?></td>
                <td><?= View::h($event['action']) ?></td>
                <td><?= View::h($event['old_state'] ?? '—') ?></td>
                <td><?= View::h($event['new_state'] ?? '—') ?></td>
                <td><?= View::h($event['comment'] ?? '—') ?></td>
            </tr>
        <?php endforeach; ?>
        </tbody>
    </table>
<?php endif; ?>
<?php View::footer(); ?>
