<?php
/**
 * B3 · Consumer · My premises (list and add)
 * [project.pdf §1.1 p.5: a consumer may have several premises; Premise ID, address, WGS84 coordinates,
 *  usage (residential, commercial, industrial, agricultural) and district / municipality / parish / postal code]
 * Procedures: sp_ListMyPremises, sp_ListSuppliers, sp_AddPremise.
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';
require __DIR__ . '/../../areas/consumer/lib.php';

use Mdms\{Auth, Csrf, Db, DbError, View};
use Mdms\Consumer as C;

Auth::requireRole('CONSUMER');

$error = null;
$form = ['address' => '', 'latitude' => '', 'longitude' => '', 'usage_type' => 'RESIDENTIAL', 'district' => C\DISTRICTS[0],
         'municipality' => '', 'parish' => '', 'postal_code' => '', 'prosumer_scheme' => 'NONE', 'supplier_org_id' => ''];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    foreach ($form as $k => $_) {
        $form[$k] = trim((string) ($_POST[$k] ?? ''));
    }
    $lat = is_numeric($form['latitude']) ? $form['latitude'] : null;
    $lon = is_numeric($form['longitude']) ? $form['longitude'] : null;
    $supplier = ctype_digit($form['supplier_org_id']) ? (int) $form['supplier_org_id'] : null;
    try {
        if ($lat === null || $lon === null) {
            throw new DbError(DbError::INPUT, 50004, 422, 'Invalid input: the coordinates must be numbers (WGS84, e.g. 35.1856 and 33.3823).');
        }
        // the procedure validates every field again (50004) and logs the creation
        $res = Db::rows('sp_AddPremise', [
            Db::nv($form['address'], 250), $lat, $lon, $form['usage_type'], Db::nv($form['district'], 30),
            Db::nv($form['municipality'], 80), Db::nv($form['parish'], 80), $form['postal_code'],
            $form['prosumer_scheme'], $supplier,
        ]);
        View::flash('ok', 'Premise #' . (int) ($res[0]['premise_id'] ?? 0) . ' added. A technician installs its meter after an officer creates the installation job.');
        header('Location: /consumer/', true, 303);
        exit;
    } catch (DbError $e) {
        $error = $e;
    }
}

$premises = C\premises();
$suppliers = Db::rows('sp_ListSuppliers');
$supplierMap = ['' => '— none yet —'];
foreach ($suppliers as $s) {
    $supplierMap[(string) $s['supplier_org_id']] = (string) $s['supplier_name'];
}

View::header('My premises');
if ($error) {
    View::error($error);
}
?>
<p class="muted">Every premise has its own Premise ID. A premise can have one meter in service; replaced meters stay in its history.</p>

<?php if ($premises === []): ?>
  <p class="flash">You have no premise yet. Add one below.</p>
<?php else: ?>
  <div class="table-wrap"><table>
    <thead><tr><th>Premise ID</th><th>Address and area</th><th>WGS84</th><th>Usage / scheme</th><th>Supplier</th><th>Meter</th><th>Threshold</th><th></th></tr></thead>
    <tbody>
    <?php foreach ($premises as $p): $id = (int) $p['premise_id']; ?>
      <tr>
        <td>#<?= $id ?></td>
        <td><?= View::h($p['address']) ?><div class="muted small"><?= View::h($p['parish']) ?>, <?= View::h($p['municipality']) ?>,
          <?= View::h($p['district']) ?> <?= View::h($p['postal_code']) ?></div></td>
        <td class="mono small"><?= View::h(C\num($p['latitude'], 6)) ?><br><?= View::h(C\num($p['longitude'], 6)) ?></td>
        <td><?= View::h(C\USAGE_TYPES[$p['usage_type']] ?? $p['usage_type']) ?><div class="muted small"><?= View::h($p['prosumer_scheme']) ?></div></td>
        <td><?= View::h($p['supplier_name'] ?? '—') ?></td>
        <td><?= $p['meter_id'] === null ? '<span class="muted">not installed</span>'
                : '<span class="mono">' . View::h($p['serial_number']) . '</span><div><span class="badge">' . View::h($p['meter_status']) . '</span></div>' ?></td>
        <td><?= $p['monthly_threshold_kwh'] === null ? '—' : View::h(C\num($p['monthly_threshold_kwh'], 1)) . ' kWh' ?></td>
        <td class="links">
          <a href="/consumer/readings.php?premise_id=<?= $id ?>">Readings</a>
          <a href="/consumer/aggregates.php?premise_id=<?= $id ?>">Totals</a>
          <a href="/consumer/events.php?premise_id=<?= $id ?>">Events</a>
        </td>
      </tr>
    <?php endforeach; ?>
    </tbody>
  </table></div>
<?php endif; ?>

<h2>Add a premise</h2>
<form method="post" action="/consumer/" class="card wide">
  <?= Csrf::field() ?>
  <label>Address <input name="address" required maxlength="250" value="<?= View::h($form['address']) ?>"></label>
  <div class="row">
    <label>Latitude (WGS84) <input name="latitude" required inputmode="decimal" placeholder="35.185600" value="<?= View::h($form['latitude']) ?>"></label>
    <label>Longitude (WGS84) <input name="longitude" required inputmode="decimal" placeholder="33.382300" value="<?= View::h($form['longitude']) ?>"></label>
  </div>
  <div class="row">
    <label>Usage <select name="usage_type"><?= C\options(C\USAGE_TYPES, $form['usage_type']) ?></select></label>
    <label>District <select name="district"><?= C\options(array_combine(C\DISTRICTS, C\DISTRICTS), $form['district']) ?></select></label>
  </div>
  <div class="row">
    <label>Municipality <input name="municipality" required maxlength="80" value="<?= View::h($form['municipality']) ?>"></label>
    <label>Parish <input name="parish" required maxlength="80" value="<?= View::h($form['parish']) ?>"></label>
    <label>Postal code <input name="postal_code" required pattern="[0-9]{4}" maxlength="4" inputmode="numeric" value="<?= View::h($form['postal_code']) ?>"></label>
  </div>
  <div class="row">
    <label>Prosumer scheme <select name="prosumer_scheme"><?= C\options(C\SCHEMES, $form['prosumer_scheme']) ?></select></label>
    <label>Supplier <select name="supplier_org_id"><?= C\options($supplierMap, $form['supplier_org_id']) ?></select></label>
  </div>
  <button type="submit">Add premise</button>
</form>
<?php
View::footer();
