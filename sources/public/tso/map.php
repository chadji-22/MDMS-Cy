<?php
/**
 * B9 · TSO / DSO / officer · Map of the transformers (with their geofences) and the meters (bonus, project.pdf p.2)
 * Leaflet is served from this site (assets/leaflet), so only the background tiles come from outside; without them the
 * rectangles and the points are still drawn. The data comes from /tso/map-data.php.
 */
declare(strict_types=1);
require __DIR__ . '/../../src/bootstrap.php';

use Mdms\{Auth, View};

Auth::requireRole('TSO', 'DSO', 'SYSTEM_OFFICER', 'SYSTEM_ADMIN');

View::$cspExtra['img-src'][] = 'https://tile.openstreetmap.org';
View::header('Map');
?>
<link rel="stylesheet" href="/assets/leaflet/leaflet.css">
<link rel="stylesheet" href="/assets/map.css">
<p class="muted">Click a rectangle or a transformer for its current state, a point for a meter, or anywhere else to find the geofence
  of that place.</p>
<form class="filters" id="map-filters">
  <label>Level <select name="level" id="map-level"><option value="">All levels</option></select></label>
  <label class="check"><input type="checkbox" id="map-meters" checked> Show meters</label>
</form>
<p id="map-message" class="flash" role="status">Loading the map…</p>
<div id="map" role="region" aria-label="Map of the grid"></div>
<p class="muted small">Colour = load of the transformer: green up to 70 %, orange up to 100 %, red above, grey no data.
  Background: © OpenStreetMap contributors. Library: Leaflet 1.9.4 (BSD-2, see assets/leaflet/LICENSE).</p>
<script src="/assets/leaflet/leaflet.js" defer></script>
<script src="/assets/map.js" defer></script>
<?php
View::footer();
