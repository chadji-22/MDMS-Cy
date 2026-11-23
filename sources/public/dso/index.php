<?php
/**
 * B7 · DSO / officer · Overview of the telemetry chain: ingest -> VEE -> decide suspects -> finalize
 * [project.pdf §3.1-§3.2 p.8-9]
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, Db, View};

Auth::requireRole('DSO', 'SYSTEM_OFFICER');

$suspects = count(Db::rows('sp_ListSuspectReadings', [null, null, 1, 500]));
$critical = Db::rows('sp_GetEvents', [null, 'CRITICAL', null, null, 1, 5]);

View::header('Telemetry and VEE');
?>
<ul class="cards">
  <li><a href="/dso/ingest.php">1. Ingest packets</a></li>
  <li><a href="/dso/vee.php">2. Run VEE</a></li>
  <li><a href="/dso/suspects.php">3. Decide suspect readings (<?= $suspects >= 500 ? '500 or more' : $suspects ?>)</a></li>
  <li><a href="/dso/finalize.php">4. Finalize a day</a></li>
  <?php if (Auth::role() === 'DSO'): ?><li><a href="/dso/reports.php">Network reports</a></li><?php endif; ?>
  <li><a href="/dso/events.php">Events</a></li>
</ul>
<h2>Latest critical events</h2>
<?php if ($critical === []): ?>
  <p class="muted">No critical events.</p>
<?php else: ?>
  <div class="table-wrap"><table>
    <thead><tr><th>Time (UTC)</th><th>Event</th><th>Where</th><th>Description</th></tr></thead>
    <tbody>
    <?php foreach ($critical as $e): ?>
      <tr><td class="mono"><?= View::h(substr((string) $e['event_timestamp'], 0, 16)) ?></td><td><?= View::h($e['event_type']) ?></td>
        <td><?= View::h($e['serial_number'] ?? $e['transformer_name'] ?? '—') ?></td><td><?= View::h($e['description']) ?></td></tr>
    <?php endforeach; ?>
    </tbody>
  </table></div>
<?php endif; ?>
<?php
View::footer();
