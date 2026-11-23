<?php
/**
 * B4 · Supplier / aggregator · Description of the JSON endpoints ("APIs", project.pdf §II.Ε p.4, §5.1 p.10)
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, View};

Auth::requireRole('SUPPLIER', 'AGGREGATOR');

$endpoints = [
    ['/market/api/portfolio.php', 'none', 'Customers, premises and meters per district.'],
    ['/market/api/day-ahead.php', 'from, to (YYYY-MM-DD, inclusive), level (1 = low voltage), root (transformer, optional)', 'Validated, final daily energy per transformer.'],
    ['/market/api/intraday.php', 'from, to (YYYY-MM-DDTHH:MM, UTC, at most 24 hours), level', 'Provisional 15-minute energy per transformer.'],
];
View::header('Data for other systems');
?>
<p>The same figures as the pages, as JSON, for your own forecasting tools. The same rules apply: only your organization, and no
  group with fewer than 3 meters.</p>
<div class="table-wrap"><table>
  <thead><tr><th>Address (GET)</th><th>Parameters</th><th>Content</th></tr></thead>
  <tbody>
  <?php foreach ($endpoints as [$path, $parameters, $content]): ?>
    <tr><td><a href="<?= View::h($path) ?>"><?= View::h($path) ?></a></td><td><?= View::h($parameters) ?></td><td><?= View::h($content) ?></td></tr>
  <?php endforeach; ?>
  </tbody>
</table></div>
<h2>Answer</h2>
<pre class="card wide">{"filters":{"from":"2026-10-30","to":"2026-10-31","level":2,"root":null},
 "count":1,
 "rows":[{"day":"2026-10-30","transformer_id":4,"transformer_name":"TX-L2 Nicosia West",
          "import_kwh":31.2,"export_kwh":4.5,"net_kwh":26.7,"meter_count":3}]}</pre>
<p class="muted">The numbers are an example. An endpoint uses the login session (cookie). Errors have the form
  <code>{"error":"..."}</code>: 401 not logged in, 403 wrong role, 422 wrong parameter.</p>
<?php
View::footer();
