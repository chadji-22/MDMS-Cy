<?php
/**
 * B8 · TSO · Add or change a transformer and its geofence
 * [project.pdf §4.1 p.9]   sp_UpsertTransformer (the values shown come from sp_GetTransformerTree)
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Csrf, Db, DbError, Ui, Validate, View};

Auth::requireRole('TSO');

$isPost = $_SERVER['REQUEST_METHOD'] === 'POST';
if ($isPost) {
    Csrf::verify();
}
$tree = Db::rows('sp_GetTransformerTree', [null]);
$byId = array_column($tree, null, 'transformer_id');
$idText = $isPost ? Validate::post('id') : Ui::get('id');
$id = $idText === '' ? null : Validate::id($idText);
if ($idText !== '' && ($id === null || !isset($byId[$id]))) {
    View::fail(404, 'Transformer not found', 'Choose a transformer from the tree.');
}

$names = ['name', 'level', 'capacity_kva', 'latitude', 'longitude', 'min_lat', 'min_lon', 'max_lat', 'max_lon', 'parent_transformer_id'];
$in = [];
foreach ($names as $name) {
    $in[$name] = $isPost ? trim(Validate::post($name)) : (string) ($id === null ? '' : ($byId[$id][$name] ?? ''));
}
$error = null;
if ($isPost) {
    try {
        $title = Validate::text($in['name'], 100);
        $level = Validate::int($in['level'], 1, 255);
        $capacity = Validate::decimal($in['capacity_kva'], 10, 2);
        $parent = $in['parent_transformer_id'] === '' ? null : Validate::id($in['parent_transformer_id']);
        if ($title === null || $level === null || $capacity === null || ($in['parent_transformer_id'] !== '' && $parent === null)) {
            throw Ui::invalid('give a name, a level, a capacity and a parent of the list.');
        }
        $geo = [];
        foreach (['latitude', 'longitude', 'min_lat', 'min_lon', 'max_lat', 'max_lon'] as $name) {
            $geo[$name] = $in[$name] === '' ? null : Validate::decimal($in[$name], 9, 6, true);
            if ($in[$name] !== '' && $geo[$name] === null) {
                throw Ui::invalid('a coordinate must be a number with at most 6 decimals.');
            }
        }
        $r = Db::row('sp_UpsertTransformer', [$id, Db::nv($title, 100), $level, $capacity, $geo['latitude'], $geo['longitude'],
            $geo['min_lat'], $geo['min_lon'], $geo['max_lat'], $geo['max_lon'], $parent]);
        View::flash('ok', 'Transformer ' . (int) ($r['transformer_id'] ?? 0) . ' was saved.');
        Ui::redirect('/tso/tree.php');
    } catch (DbError $e) {
        $error = $e;
        http_response_code($e->httpStatus());
    }
}
$parents = Ui::transformerOptions($tree);
unset($parents[$id ?? 0]);
$coordinate = static fn(string $name, string $label, bool $required = false): string =>
    '<label>' . View::h($label) . ' <input name="' . View::h($name) . '" inputmode="decimal" value="' . View::h($in[$name]) . '"' . ($required ? ' required' : '') . '></label>';

View::header($id === null ? 'Add a transformer' : 'Change transformer ' . $id);
if ($error) {
    View::error($error);
}
?>
<form method="post" action="<?= View::base() ?>/tso/transformer.php" class="card wide">
  <?= Csrf::field() ?>
  <input type="hidden" name="id" value="<?= View::h($id) ?>">
  <div class="row">
    <label>Name <input name="name" maxlength="100" value="<?= View::h($in['name']) ?>" required></label>
    <label>Level (1 = low voltage) <input type="number" name="level" min="1" max="255" value="<?= View::h($in['level']) ?>" required></label>
    <label>Capacity (kVA) <input name="capacity_kva" inputmode="decimal" value="<?= View::h($in['capacity_kva']) ?>" required></label>
  </div>
  <label>Parent <select name="parent_transformer_id"><?= Ui::options(['' => 'None (root of a tree)'] + $parents, $in['parent_transformer_id']) ?></select></label>
  <div class="row"><?= $coordinate('latitude', 'Latitude', true) ?><?= $coordinate('longitude', 'Longitude', true) ?></div>
  <h2>Geofence (rectangle; all four or none)</h2>
  <div class="row"><?= $coordinate('min_lat', 'South') ?><?= $coordinate('min_lon', 'West') ?><?= $coordinate('max_lat', 'North') ?><?= $coordinate('max_lon', 'East') ?></div>
  <button type="submit">Save</button>
</form>
<p><a href="<?= View::base() ?>/tso/tree.php">Back to the tree</a></p>
<?php
View::footer();
