<?php
/**
 * B8 · TSO / DSO / officer · The transformer hierarchy, whatever its depth
 * [project.pdf §4.1-§4.2 p.9-10; UC-17]   sp_GetTransformerTree, sp_RefreshTransformerAncestors
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, Ui, Validate, View};

Auth::requireRole('TSO', 'DSO', 'SYSTEM_OFFICER', 'SYSTEM_ADMIN');

$canRefresh = in_array(Auth::role(), ['TSO', 'DSO'], true);
$error = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    Csrf::verify();
    Auth::requireRole('TSO', 'DSO');
    try {
        $id = Validate::id(Validate::post('transformer_id'));
        $slot = Validate::dateTime(Validate::post('slot'));
        if ($id === null || $slot === null) {
            throw Ui::invalid('choose a level-1 transformer and a slot.');
        }
        $r = Db::row('sp_RefreshTransformerAncestors', [$id, $slot]);
        View::flash('ok', 'Transformer ' . $id . ' and its ancestors were computed for ' . Ui::ts($r['reference_15_min'] ?? null)
            . ' (' . (int) ($r['nodes_updated'] ?? 0) . ' nodes).');
        Ui::redirect('/tso/tree.php');
    } catch (DbError $e) {
        $error = $e;
        http_response_code($e->httpStatus());
    }
}
$root = Validate::id(Ui::get('root'));
$tree = [];
try {
    $tree = Db::rows('sp_GetTransformerTree', [$root]);
} catch (DbError $e) {
    $error ??= $e;
    http_response_code($e->httpStatus());
}

View::header('Transformer tree');
if ($error) {
    View::error($error);
}
?>
<?php if ($root !== null): ?><p><a href="/tso/tree.php">Show the whole tree</a></p><?php endif; ?>
<?php if (Auth::role() === 'TSO'): ?><p><a href="/tso/transformer.php">Add a transformer</a></p><?php endif; ?>
<?php if ($tree === [] && !$error): ?>
  <p class="flash">There are no transformers yet.</p>
<?php elseif ($tree !== []): ?>
<div class="table-wrap"><table>
  <thead><tr><th>Transformer</th><th class="num">Level</th><th class="num">Capacity (kVA)</th><th>Geofence</th><th class="num">Meters connected</th><th class="num">Reporting</th><th class="num">Import (kWh)</th><th class="num">Export (kWh)</th><th>Slot (UTC)</th><th></th></tr></thead>
  <tbody><?php foreach ($tree as $t): ?>
    <tr><td><?= View::h(str_repeat('— ', (int) $t['depth']) . $t['name']) ?> <span class="muted small">no. <?= (int) $t['transformer_id'] ?></span></td>
      <td class="num"><?= (int) $t['level'] ?></td><td class="num"><?= View::h(Ui::num($t['capacity_kva'], 0)) ?></td><td><?= $t['min_lat'] === null ? '—' : 'yes' ?></td>
      <td class="num"><?= (int) $t['meters_connected'] ?></td><td class="num"><?= $t['meters_reporting'] === null ? '—' : (int) $t['meters_reporting'] ?></td>
      <td class="num"><?= View::h(Ui::num($t['import_kwh'])) ?></td><td class="num"><?= View::h(Ui::num($t['export_kwh'])) ?></td>
      <td class="mono"><?= View::h(Ui::ts($t['reference_15_min'])) ?></td>
      <td class="links"><a href="/tso/tree.php?root=<?= (int) $t['transformer_id'] ?>">Subtree</a>
        <?php if (Auth::role() === 'TSO'): ?><a href="/tso/transformer.php?id=<?= (int) $t['transformer_id'] ?>">Edit</a><?php endif; ?></td></tr>
  <?php endforeach; ?></tbody>
</table></div>
<?php endif; ?>

<?php if ($canRefresh && $tree !== []): ?>
<h2>Refresh one transformer and its ancestors</h2>
<form method="post" action="/tso/tree.php" class="filters">
  <?= Csrf::field() ?>
  <label>Level-1 transformer <select name="transformer_id" required><?= Ui::options(['' => 'Choose'] + Ui::transformerOptions($tree, 1), '') ?></select></label>
  <label>Slot (UTC) <input type="datetime-local" step="900" name="slot" required></label>
  <button type="submit">Refresh</button>
</form>
<p class="muted">Only this transformer is read again; each ancestor becomes the sum of its children, level by level.</p>
<?php endif; ?>
<?php
View::footer();
