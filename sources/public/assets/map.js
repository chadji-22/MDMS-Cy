/* B9: map of the grid. Every text of the database is put in the page with textContent, never as HTML. */
(function () {
  'use strict';
  var message = document.getElementById('map-message');
  function say(text, isError) {
    message.textContent = text;
    message.className = 'flash' + (isError ? ' error' : '');
    message.hidden = text === '';
  }
  if (!window.L) { say('The map library could not be loaded.', true); return; }

  var map = L.map('map').setView([35.05, 33.3], 9);          // Cyprus
  // the site sends no Referer to other sites; the tile server asks for the origin
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19, referrerPolicy: 'origin', attribution: '© OpenStreetMap contributors'
  }).addTo(map);
  var boxes = L.layerGroup().addTo(map);
  var meters = L.layerGroup().addTo(map);
  var data = { transformers: [], meters: [] };

  function colour(load) {
    if (load === null) { return '#7a858f'; }
    return load > 100 ? '#a4262c' : load > 70 ? '#c77700' : '#1e6b3a';
  }
  function popup(title, rows) {
    var box = document.createElement('div'), head = document.createElement('h3'), table = document.createElement('table');
    head.textContent = title;
    rows.forEach(function (r) {
      var tr = table.insertRow(), th = document.createElement('th');
      th.textContent = r[0];
      tr.appendChild(th);
      tr.insertCell().textContent = r[1];
    });
    box.appendChild(head);
    box.appendChild(table);
    return box;
  }
  function kwh(v) { return v === null ? 'no data' : v.toFixed(3) + ' kWh'; }
  function state(t) {
    return popup(t.name, [
      ['Level', String(t.level)], ['Capacity', t.capacity + ' kVA'], ['Slot (UTC)', t.slot || 'not computed'],
      ['Import', kwh(t.import)], ['Export', kwh(t.export)], ['Load', t.load === null ? 'no data' : t.load + ' %'],
      ['Meters connected', String(t.meters)], ['Meters reporting', t.reporting === null ? 'no data' : String(t.reporting)]
    ]);
  }
  function draw() {
    var level = document.getElementById('map-level').value;
    boxes.clearLayers();
    data.transformers.forEach(function (t) {                  // the tree order puts parents first, children stay on top
      if (level !== '' && String(t.level) !== level) { return; }
      if (t.box) {
        L.rectangle(t.box, { color: colour(t.load), weight: 2, fillOpacity: 0.06 }).bindPopup(function () { return state(t); }).addTo(boxes);
      }
      L.circleMarker([t.lat, t.lon], { radius: 5 + t.level, color: colour(t.load), fillOpacity: 0.6 })
        .bindPopup(function () { return state(t); }).addTo(boxes);
    });
  }
  function drawMeters() {
    meters.clearLayers();
    if (!document.getElementById('map-meters').checked) { return; }
    data.meters.forEach(function (m) {
      L.circleMarker([m.lat, m.lon], { radius: 4, color: m.status === 'ACTIVE' ? '#0b5cad' : '#7a858f', fillOpacity: 0.9, weight: 1 })
        .bindPopup(function () {
          return popup('Meter ' + m.serial, [['Status', m.status], ['Transformer', m.transformer || '—']]);
        }).addTo(meters);
    });
  }
  function getJson(url) {
    return fetch(url, { credentials: 'same-origin' }).then(function (r) {
      return r.json().then(function (j) {
        if (!r.ok) { throw new Error(j.error || 'The data could not be loaded.'); }
        return j;
      });
    });
  }

  document.getElementById('map-filters').addEventListener('submit', function (e) { e.preventDefault(); });
  document.getElementById('map-level').addEventListener('change', draw);
  document.getElementById('map-meters').addEventListener('change', drawMeters);

  map.on('click', function (e) {
    var p = e.latlng.wrap();
    getJson('/tso/map-data.php?lat=' + p.lat.toFixed(6) + '&lon=' + p.lng.toFixed(6)).then(function (j) {
      var rows = j.path.map(function (n) { return ['Level ' + n.level, n.name]; });
      L.popup().setLatLng(e.latlng)
        .setContent(popup(rows.length ? 'Geofence of this point' : 'This point is in no geofence', rows)).openOn(map);
    }).catch(function (err) { say(err.message, true); });
  });

  getJson('/tso/map-data.php').then(function (j) {
    data = j;
    var levels = {}, select = document.getElementById('map-level');
    j.transformers.forEach(function (t) { levels[t.level] = true; });
    Object.keys(levels).sort(function (a, b) { return a - b; }).forEach(function (l) {
      var o = document.createElement('option');
      o.value = l;
      o.textContent = 'Level ' + l;
      select.appendChild(o);
    });
    draw();
    drawMeters();
    var points = [];
    j.transformers.forEach(function (t) { points = points.concat(t.box || [[t.lat, t.lon]]); });
    if (points.length) { map.fitBounds(points, { padding: [15, 15] }); }
    say(j.complete ? '' : 'There are more meters than the map shows.', false);
  }).catch(function (err) { say(err.message, true); });
}());
