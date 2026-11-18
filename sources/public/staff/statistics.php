<?php
declare(strict_types=1);

require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Db, DbError, View};

Auth::requireRole('SYSTEM_ADMIN', 'SYSTEM_OFFICER');

$today = new DateTimeImmutable('today', new DateTimeZone('UTC'));
$from = filter_input(INPUT_GET, 'from') ?? $today->modify('-29 days')->format('Y-m-d');
$until = filter_input(INPUT_GET, 'until') ?? $today->modify('+1 day')->format('Y-m-d');
$validDate = static function (string $date): bool {
    return preg_match('/\A([0-9]{4})-([0-9]{2})-([0-9]{2})\z/', $date, $parts) === 1
        && checkdate((int) $parts[2], (int) $parts[3], (int) $parts[1]);
};
$valid = is_string($from) && is_string($until) && $validDate($from) && $validDate($until) && $from < $until;
$groups = [];
$error = null;

if ($valid) {
    try {
        foreach (Db::rows('sp_ReportSystemStatistics', [$from . 'T00:00:00', $until . 'T00:00:00']) as $row) {
            $groups[$row['section']][] = $row;
        }
    } catch (DbError $exception) {
        $error = $exception;
    }
} else {
    http_response_code(400);
}

$sections = [
    'METERS_BY_DISTRICT_STATUS' => ['Current meters by district and status', 'District', 'Status', 'Meters'],
    'READINGS_BY_STATUS' => ['Readings by status', 'Status', null, 'Readings'],
    'VEE_RULE_PCT' => ['Share of readings by VEE rule', 'Rule', null, 'Share (%)'],
    'CONSUMPTION_BY_MONTH_DISTRICT' => ['Consumption by month and district', 'Month', 'District', 'kWh'],
    'BILLED_BY_SUPPLIER' => ['Billed amounts by supplier', 'Supplier', null, 'Amount (€)'],
    'COLLECTED_BY_SUPPLIER' => ['Collected amounts by supplier', 'Supplier', null, 'Amount (€)'],
    'SERVICE_FEES' => ['Collected service fees', 'Service', null, 'Amount (€)'],
    'WORK_ORDERS_BY_TYPE_STATUS' => ['Work orders by type and status', 'Type', 'Status', 'Orders'],
    'EVENTS_BY_TYPE' => ['Events by type and severity', 'Type', 'Severity', 'Events'],
];

View::header('System statistics');
?>
<form method="get" action="/staff/statistics.php" class="card">
    <label>From date (UTC) <input type="date" name="from" value="<?= View::h($from) ?>" required></label>
    <label>Until date (UTC, exclusive) <input type="date" name="until" value="<?= View::h($until) ?>" required></label>
    <button type="submit">Run report</button>
</form>
<?php if (!$valid): ?>
    <p class="flash error" role="alert">Choose an until date later than the from date.</p>
<?php elseif ($error !== null): ?>
    <?php View::error($error); ?>
<?php elseif ($groups === []): ?>
    <p>No statistics are available for this report.</p>
<?php else: ?>
    <?php foreach ($sections as $section => [$title, $firstLabel, $secondLabel, $valueLabel]): ?>
        <h2><?= View::h($title) ?></h2>
        <?php if (!isset($groups[$section])): ?>
            <p>No data in the selected period.</p>
        <?php else: ?>
            <table>
                <thead><tr><th><?= View::h($firstLabel) ?></th><?php if ($secondLabel !== null): ?><th><?= View::h($secondLabel) ?></th><?php endif; ?><th><?= View::h($valueLabel) ?></th></tr></thead>
                <tbody>
                <?php foreach ($groups[$section] as $row): ?>
                    <?php $value = preg_replace('/\A(-?)\./', '${1}0.', (string) $row['value']); ?>
                    <?php if (str_contains($value, '.')) $value = rtrim(rtrim($value, '0'), '.'); ?>
                    <tr>
                        <td><?= View::h($row['label_1']) ?></td>
                        <?php if ($secondLabel !== null): ?><td><?= View::h($row['label_2'] ?? '—') ?></td><?php endif; ?>
                        <td><?= View::h($value) ?></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        <?php endif; ?>
    <?php endforeach; ?>
<?php endif; ?>
<?php View::footer(); ?>
