<?php
declare(strict_types=1);

require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, View};

Auth::requireRole('SYSTEM_OFFICER');
$isPost = $_SERVER['REQUEST_METHOD'] === 'POST';
if ($isPost) {
    Csrf::verify();
}

$catalogs = [
    'meter-types' => ['Meter types', 'meter_type_id', 'sp_UpsertMeterType', [
        'type_name' => ['Name', 'ascii', 50],
        'connection_phases' => ['Connection phases', 'select', ['1' => '1', '3' => '3']],
        'max_amps' => ['Maximum current (A)', 'decimal', [5, 1, false]],
    ]],
    'service-types' => ['Service types', 'service_type_id', 'sp_UpsertServiceType', [
        'service_name' => ['Name', 'unicode', 100],
        'fee' => ['Fee (€)', 'decimal', [8, 2, false]],
        'is_active' => ['Status', 'select', ['1' => 'Active', '0' => 'Inactive']],
    ]],
    'obis' => ['OBIS codes', 'obis_code', 'sp_UpsertObisCode', [
        'obis_code' => ['Code', 'ascii', 20],
        'description' => ['Description', 'unicode', 200],
        'unit' => ['Unit', 'ascii', 10],
        'measurement_kind' => ['Measurement kind', 'select', ['INSTANTANEOUS' => 'Instantaneous', 'CUMULATIVE' => 'Cumulative']],
        'valid_min' => ['Valid minimum', 'decimal', [14, 4, true], false],
        'valid_max' => ['Valid maximum', 'decimal', [14, 4, true], false],
    ]],
    'tariffs' => ['Tariffs', 'tariff_id', 'sp_UpsertTariff', [
        'tariff_name' => ['Name', 'unicode', 100],
        'rate' => ['Rate (€/kWh)', 'decimal', [6, 4, false]],
        'valid_from' => ['Valid from', 'date', null],
        'valid_to' => ['Valid through', 'date', null, false],
    ]],
];

$catalog = filter_input(INPUT_GET, 'catalog') ?? 'meter-types';
if (!isset($catalogs[$catalog])) {
    View::fail(404, 'Catalog unavailable', 'Select a reference catalog.');
}
[$title, $key, $procedure, $fields] = $catalogs[$catalog];
$formatDecimal = static fn (string $value): string => preg_replace('/\A(-?)\./', '${1}0.', $value);
$route = View::url('/staff/catalogs.php?catalog=' . rawurlencode($catalog));   // full URL path (base included)
$editKey = filter_input(INPUT_GET, 'edit');
$rows = [];
$selected = null;
$error = null;
try {
    $rows = Db::rows('sp_ListReferenceCatalog', [$catalog]);
} catch (DbError $exception) {
    $error = $exception;
}

if ($editKey !== null && $error === null) {
    foreach ($rows as $row) {
        if ((string) $row[$key] === $editKey) {
            $selected = $row;
            break;
        }
    }
    if ($selected === null) {
        View::fail(404, 'Entry unavailable', 'The selected catalog entry was not found.');
    }
}

$formUrl = $selected === null ? $route : $route . '&edit=' . rawurlencode((string) $selected[$key]);
$values = $selected ?? ['is_active' => '1'];
if ($catalog === 'service-types' && $selected !== null) {
    $values['is_active'] = (string) (int) $selected['is_active'];
}
$invalid = [];
if ($isPost && $error === null) {
    $params = $catalog === 'obis' ? [] : [$selected === null ? null : (int) $selected[$key]];
    foreach ($fields as $field => $definition) {
        [$label, $type, $options] = $definition;
        $required = $definition[3] ?? true;
        $value = $selected !== null && $field === 'obis_code'
            ? (string) $selected[$key] : trim((string) filter_input(INPUT_POST, $field));
        if ($type === 'decimal') {
            $value = $formatDecimal($value);
        }
        $values[$field] = $value;
        if ($value === '' && !$required) {
            $params[] = null;
            continue;
        }

        $valid = match ($type) {
            'ascii' => preg_match('/\A[ -~]{1,' . $options . '}\z/', $value) === 1,
            'unicode' => preg_match('/\A.{1,' . $options . '}\z/u', $value) === 1,
            'select' => array_key_exists($value, $options),
            'decimal' => preg_match('/\A' . ($options[2] ? '-?' : '') . '[0-9]{1,' . $options[0]
                . '}(?:\.[0-9]{1,' . $options[1] . '})?\z/', $value) === 1,
            'date' => preg_match('/\A([0-9]{4})-([0-9]{2})-([0-9]{2})\z/', $value, $parts) === 1
                && checkdate((int) $parts[2], (int) $parts[3], (int) $parts[1]),
        };
        if (!$valid || ($field === 'max_amps' && (float) $value <= 0)) {
            $invalid[] = $label;
        }
        $params[] = $type === 'unicode' ? Db::nv($value, $options) : $value;
    }
    if ($catalog === 'obis') {
        $params[] = $selected === null ? 1 : 0;
    }

    if ($invalid === []) {
        try {
            Db::callAsActor($procedure, $params);
            View::flash('ok', $selected === null ? 'Catalog entry added.' : 'Catalog entry updated.');
            header('Location: ' . $route, true, 303);
            exit;
        } catch (DbError $exception) {
            $error = $exception;
            http_response_code($error->httpStatus());
        }
    } else {
        http_response_code(400);
    }
}

View::header($title);
?>
<nav aria-label="Reference catalogs">
    <ul class="cards">
        <?php foreach ($catalogs as $id => $entry): ?>
            <li><a href="<?= View::base() ?>/staff/catalogs.php?catalog=<?= View::h($id) ?>"<?= $id === $catalog ? ' aria-current="page"' : '' ?>><?= View::h($entry[0]) ?></a></li>
        <?php endforeach; ?>
    </ul>
</nav>
<?php if ($error !== null): ?>
    <?php View::error($error); ?>
<?php endif; ?>
<?php if ($invalid !== []): ?>
    <p class="flash error" role="alert">Check these fields: <?= View::h(implode(', ', $invalid)) ?>.</p>
<?php endif; ?>
<?php if ($error === null || $isPost): ?>
    <h2><?= $selected === null ? 'Add entry' : 'Edit entry' ?></h2>
    <?php if ($selected !== null): ?><p><a href="<?= View::h($route) ?>">Cancel edit</a></p><?php endif; ?>
    <form method="post" action="<?= View::h($formUrl) ?>" class="card">
        <?= Csrf::field() ?>
        <?php foreach ($fields as $field => $definition): ?>
            <?php [$label, $type, $options] = $definition; ?>
            <?php $required = ($definition[3] ?? true) ? ' required' : ''; ?>
            <?php $inputValue = (string) ($values[$field] ?? ''); ?>
            <label><?= View::h($label) ?>
            <?php if ($type === 'select'): ?>
                <select name="<?= View::h($field) ?>" required>
                    <option value="">Select an option</option>
                    <?php foreach ($options as $option => $optionLabel): ?>
                        <option value="<?= View::h($option) ?>"<?= (string) ($values[$field] ?? '') === (string) $option ? ' selected' : '' ?>><?= View::h($optionLabel) ?></option>
                    <?php endforeach; ?>
                </select>
            <?php else: ?>
                <input type="<?= $type === 'date' ? 'date' : 'text' ?>" name="<?= View::h($field) ?>" value="<?= View::h($type === 'decimal' ? $formatDecimal($inputValue) : $inputValue) ?>"
                    <?= $type === 'decimal' ? 'inputmode="decimal"' : '' ?>
                    <?= is_int($options) ? 'maxlength="' . $options . '"' : '' ?>
                    <?= $selected !== null && $field === 'obis_code' ? 'readonly' : '' ?><?= $required ?>>
            <?php endif; ?>
            </label>
        <?php endforeach; ?>
        <button type="submit"><?= $selected === null ? 'Add entry' : 'Save changes' ?></button>
    </form>
<?php endif; ?>

<h2>Existing entries</h2>
<?php if ($rows === [] && $error === null): ?>
    <p>No entries in this catalog.</p>
<?php elseif ($rows !== []): ?>
    <table>
        <thead><tr><?php foreach ($fields as [$label]): ?><th><?= View::h($label) ?></th><?php endforeach; ?><th>Action</th></tr></thead>
        <tbody>
        <?php foreach ($rows as $row): ?>
            <tr>
                <?php foreach ($fields as $field => [, $type, $options]): ?>
                    <?php $value = $row[$field]; ?>
                    <?php if ($type === 'decimal' && $value !== null) $value = $formatDecimal((string) $value); ?>
                    <td><?= View::h($type === 'select' ? ($options[$value] ?? '—') : ($value ?? '—')) ?></td>
                <?php endforeach; ?>
                <td><a href="<?= View::h($route . '&edit=' . rawurlencode((string) $row[$key])) ?>">Edit</a></td>
            </tr>
        <?php endforeach; ?>
        </tbody>
    </table>
<?php endif; ?>
<?php View::footer(); ?>
