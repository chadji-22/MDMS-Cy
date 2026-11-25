<?php
declare(strict_types=1);

require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, View};

Auth::requireRole('TECHNICIAN');
$error = null;
$actions = [
    'accept' => ['status' => 'ASSIGNED', 'label' => 'Accept', 'procedure' => 'sp_AcceptWorkOrder', 'message' => 'Job accepted.'],
    'decline' => ['status' => 'ASSIGNED', 'label' => 'Decline', 'procedure' => 'sp_DeclineWorkOrder', 'message' => 'Job declined.'],
    'start' => ['status' => 'ACCEPTED', 'label' => 'Start', 'procedure' => 'sp_StartWorkOrder', 'message' => 'Job started.'],
    'complete' => ['status' => 'IN_PROGRESS', 'label' => 'Complete', 'procedure' => 'sp_CompleteWorkOrder', 'message' => 'Job completed.'],
];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    $jobId = filter_input(INPUT_POST, 'work_order_id', FILTER_VALIDATE_INT, [
        'options' => ['min_range' => 1, 'max_range' => 2147483647],
    ]);
    if ($jobId === false || $jobId === null) {
        View::fail(400, 'Invalid job', 'Select a job and try again.');
    }
    $actionName = filter_input(INPUT_POST, 'action');
    $action = $actions[$actionName] ?? null;
    if ($action === null) {
        View::fail(400, 'Invalid action', 'Reload My Jobs and try again.');
    }

    $params = [$jobId];
    if ($actionName === 'decline') {
        $reason = trim((string) filter_input(INPUT_POST, 'reason'));
        if (preg_match('/\A.{1,500}\z/su', $reason) !== 1) {
            View::fail(400, 'Invalid reason', 'Enter a reason of up to 500 characters.');
        }
        $params[] = Db::nv($reason, 500);
    } elseif ($actionName === 'complete') {
        $findings = trim((string) filter_input(INPUT_POST, 'findings'));
        $personsToNotify = trim((string) filter_input(INPUT_POST, 'persons_to_notify'));
        if ($findings === '' || preg_match('/\A.{1,2000}\z/su', $findings) !== 1
            || preg_match('/\A.{0,500}\z/su', $personsToNotify) !== 1) {
            View::fail(400, 'Invalid completion details', 'Enter findings (up to 2,000 characters) and, where needed, who to notify (up to 500 characters).');
        }

        $params[] = Db::nv($findings, 2000);
        $params[] = null;
        $params[] = Db::nv($personsToNotify === '' ? null : $personsToNotify, 500);
    }

    try {
        Db::callAsActor($action['procedure'], $params);
        View::flash('ok', $action['message']);
        header('Location: ' . View::url('/technician/'), true, 303);
        exit;
    } catch (DbError $exception) {
        $error = $exception;
    }
}

View::header('My Jobs');
if ($error !== null) {
    View::error($error);
}

try {
    $jobs = Db::rows('sp_ListMyWorkOrders');

    if ($jobs === []) {
        echo '<p>No jobs assigned to you.</p>';
    } else {
        echo '<table><thead><tr><th>Job</th><th>Type</th><th>Status</th><th>Location</th><th>Visit (UTC)</th><th>Actions</th></tr></thead><tbody>';

        foreach ($jobs as $job) {
            $jobId = View::h($job['work_order_id']);
            echo '<tr><td><a href="' . View::base() . '/technician/job.php?id=' . $jobId . '">#' . $jobId . '</a></td>'
                . '<td>' . View::h($job['work_type']) . '</td>'
                . '<td>' . View::h($job['status']) . '</td>'
                . '<td>' . View::h($job['premise_address'] ?? '—');

            if ($job['meter_latitude'] !== null && $job['meter_longitude'] !== null) {
                echo '<br><small>Meter: ' . View::h($job['meter_latitude']) . ', ' . View::h($job['meter_longitude']) . '</small>';
            } elseif ($job['premise_latitude'] !== null && $job['premise_longitude'] !== null) {
                echo '<br><small>Premise: ' . View::h($job['premise_latitude']) . ', ' . View::h($job['premise_longitude']) . '</small>';
            }

            echo '</td><td>' . View::h($job['scheduled_start'] ?? '—');
            if ($job['scheduled_end'] !== null) {
                echo '<br>' . View::h($job['scheduled_end']);
            }
            echo '</td><td>';

            foreach ($actions as $actionName => $action) {
                if ($action['status'] !== $job['status']) {
                    continue;
                }
                echo '<form method="post" action="' . View::base() . '/technician/">' . Csrf::field()
                    . '<input type="hidden" name="work_order_id" value="' . View::h($job['work_order_id']) . '">'
                    . '<input type="hidden" name="action" value="' . View::h($actionName) . '">';
                if ($actionName === 'decline') {
                    echo '<label>Reason <input name="reason" maxlength="500" required></label>';
                } elseif ($actionName === 'complete') {
                    echo '<label>Findings <textarea name="findings" maxlength="2000" required></textarea></label>';
                    if ($job['work_type'] === 'ANTI_TAMPER') {
                        echo '<label>Who to notify <input name="persons_to_notify" maxlength="500" required></label>';
                    }
                }
                echo '<button type="submit">' . View::h($action['label']) . '</button></form>';
            }

            if ($job['work_type'] === 'INSTALLATION' && in_array($job['status'], ['ACCEPTED', 'IN_PROGRESS'], true)) {
                if ($job['meter_id'] === null) {
                    echo '<a href="' . View::base() . '/technician/install-meter.php?id=' . $jobId . '">Register meter</a>';
                } else {
                    echo '<a href="' . View::base() . '/technician/meter-certificates.php?id=' . View::h($job['meter_id']) . '">Meter certificates</a>';
                }
            }

            echo '</td></tr>';
        }

        echo '</tbody></table>';
    }
} catch (DbError $error) {
    View::error($error);
}

View::footer();
