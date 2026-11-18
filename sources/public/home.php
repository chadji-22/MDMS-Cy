<?php
declare(strict_types=1);
require __DIR__ . '/../src/bootstrap.php';

use Mdms\Auth;
use Mdms\Menu;
use Mdms\View;

Auth::requireLogin();
View::header('Home');
$items = Menu::forRole(Auth::role());
?>
<p>Welcome, <strong><?= View::h(Auth::name()) ?></strong> (<?= View::h(Auth::role()) ?>).</p>
<?php if (Auth::role() === 'TECHNICIAN' && Auth::approval() !== 'APPROVED'): ?>
  <p class="flash error">Your registration is <strong><?= View::h(Auth::approval()) ?></strong>. You cannot take jobs until an officer approves it.</p>
<?php endif; ?>
<?php if ($items === []): ?>
  <p>There are no pages for your role yet.</p>
<?php else: ?>
  <ul class="cards">
    <?php foreach ($items as $it): ?>
      <li><a href="<?= View::h($it['href']) ?>"><?= View::h($it['label']) ?></a></li>
    <?php endforeach; ?>
  </ul>
<?php endif; ?>
<?php
View::footer();
