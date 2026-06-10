/* =========================================================
   Lake Texoma Nav — main application
   ========================================================= */

// ── Constants ─────────────────────────────────────────────
const LAKE_TEXOMA = [33.83, -96.59];
const INIT_ZOOM   = 12;
const MS_PER_HOUR = 3600000;
const MPS_TO_KNOTS = 1.94384;
const STORAGE_KEYS = { waypoints: 'ltn_waypoints', tracks: 'ltn_tracks' };

// ── Tile URLs ──────────────────────────────────────────────
const TILES = {
  satellite: {
    url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    attr: '© Esri, Maxar, Earthstar Geographics'
  },
  topo: {
    // USGS National Map — shows reservoir depth contours for Army Corps lakes
    url: 'https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer/tile/{z}/{y}/{x}',
    attr: '© USGS National Map'
  },
  osm: {
    url: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
    attr: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
  },
  seamark: {
    url: 'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png',
    attr: '© <a href="https://www.openseamap.org">OpenSeaMap</a>'
  }
};

// ── State ──────────────────────────────────────────────────
const state = {
  following:   true,
  addingWpt:   false,
  pendingWpt:  null,
  track: {
    recording: false,
    paused:    false,
    points:    [],
    startTime: null,
    pauseMs:   0,
    pauseStart:null,
    interval:  null
  },
  gps: { lat: null, lng: null, speed: null, heading: null, accuracy: null }
};

// ── Map Setup ──────────────────────────────────────────────
const map = L.map('map', {
  center: LAKE_TEXOMA,
  zoom:   INIT_ZOOM,
  zoomControl: true,
  attributionControl: true
});

const baseLayers = {
  satellite: L.tileLayer(TILES.satellite.url, { attribution: TILES.satellite.attr, maxZoom: 19 }),
  topo:      L.tileLayer(TILES.topo.url,      { attribution: TILES.topo.attr,      maxZoom: 19, maxNativeZoom: 16 }),
  osm:       L.tileLayer(TILES.osm.url,       { attribution: TILES.osm.attr,       maxZoom: 19 })
};

const overlayLayers = {
  seamark: L.tileLayer(TILES.seamark.url, { attribution: TILES.seamark.attr, maxZoom: 18, opacity: 0.9 })
};

baseLayers.satellite.addTo(map);
overlayLayers.seamark.addTo(map);

// ── Depth Chart Layer (TWDB official survey — nautical chart style) ──
const depthLayer    = L.layerGroup().addTo(map);
const soundingLayer = L.layerGroup().addTo(map);
let depthLoaded     = false;
let soundingsLoaded = false;

function contourStyle(ft) {
  // Index contours (every 10ft elevation interval) slightly heavier
  const isIndex = (Math.round(617 - ft) % 10 === 0);
  return {
    color:   ft <= 7 ? '#8B0000' : '#2c3e6b',   // dark red for very shallow, navy for deeper
    weight:  isIndex ? 1.5 : 0.8,
    opacity: isIndex ? 0.9 : 0.7
  };
}

function loadDepthContours() {
  if (depthLoaded) return;
  depthLoaded = true;
  showToast('Loading depth chart…');
  Promise.all([
    fetch('js/texoma_depth.geojson').then(r => r.json()),
    fetch('js/texoma_soundings.geojson').then(r => r.json())
  ]).then(([contourData, soundingData]) => {
    // Contour lines
    L.geoJSON(contourData, {
      style: f => contourStyle(f.properties.depth_ft),
      onEachFeature: (f, layer) => {
        layer.bindTooltip(`${f.properties.depth_ft} ft`, { sticky: true, className: 'depth-tip' });
      }
    }).addTo(depthLayer);

    // Depth soundings — shown at zoom 12+
    L.geoJSON(soundingData, {
      pointToLayer: (f, latlng) => {
        return L.marker(latlng, {
          icon: L.divIcon({
            className: 'sounding-label',
            html: `<span>${f.properties.depth_ft}</span>`,
            iconSize:   null,
            iconAnchor: [10, 6]
          })
        });
      }
    }).addTo(soundingLayer);

    // Only show soundings when zoomed in enough
    function updateSoundingVisibility() {
      if (map.getZoom() >= 12) {
        if (!map.hasLayer(soundingLayer) && document.getElementById('layer-depth').checked) {
          soundingLayer.addTo(map);
        }
      } else {
        if (map.hasLayer(soundingLayer)) map.removeLayer(soundingLayer);
      }
    }
    map.on('zoomend', updateSoundingVisibility);
    updateSoundingVisibility();

    showToast('Depth chart loaded');
  }).catch(() => showToast('Could not load depth data'));
}

// ── Leaflet Groups ─────────────────────────────────────────
const gpsLayer       = L.layerGroup().addTo(map);
const waypointLayer  = L.layerGroup().addTo(map);
const trackLayer     = L.layerGroup().addTo(map);
const headingLayer   = L.layerGroup().addTo(map);

let gpsMarker        = null;
let gpsAccCircle     = null;
let headingLine      = null;
let trackPolyline    = null;
let activeTrackLine  = null;
let navigationTarget = null;
let navLine          = null;

// ── GPS ────────────────────────────────────────────────────
function initGPS() {
  if (!navigator.geolocation) {
    setGPSStatus('error', 'GPS unavailable');
    return;
  }
  navigator.geolocation.watchPosition(onPosition, onPositionError, {
    enableHighAccuracy: true,
    maximumAge: 2000,
    timeout: 10000
  });
}

function onPosition(pos) {
  const { latitude: lat, longitude: lng, accuracy, speed, heading } = pos.coords;
  state.gps = { lat, lng, speed, heading, accuracy };

  setGPSStatus('locked', 'GPS locked');
  updateGPSBar(speed, heading, accuracy);
  updateGPSMarker(lat, lng, accuracy, heading);

  if (state.following) map.setView([lat, lng], map.getZoom());
  if (state.track.recording && !state.track.paused) recordTrackPoint(lat, lng);
  if (navigationTarget) updateNavLine(lat, lng);
}

function onPositionError(err) {
  setGPSStatus('error', err.code === 1 ? 'GPS denied' : 'GPS error');
}

function setGPSStatus(type, label) {
  const dot = document.querySelector('.dot');
  dot.className = 'dot dot-' + (type === 'locked' ? 'locked' : type === 'error' ? 'error' : 'searching');
  document.getElementById('gps-label').textContent = label;
}

function updateGPSBar(speed, heading, accuracy) {
  const kn = speed != null ? (speed * MPS_TO_KNOTS).toFixed(1) : '--';
  document.getElementById('speed-val').textContent = kn;
  document.getElementById('heading-val').textContent = heading != null ? Math.round(heading) : '--';
  document.getElementById('accuracy-val').textContent = accuracy != null ? Math.round(accuracy) : '--';
}

function updateGPSMarker(lat, lng, accuracy, heading) {
  if (!gpsMarker) {
    const icon = L.divIcon({ className: '', html: '<div class="gps-marker-inner"></div>', iconSize: [16,16], iconAnchor: [8,8] });
    gpsMarker = L.marker([lat, lng], { icon, zIndexOffset: 1000 }).addTo(gpsLayer);
    gpsAccCircle = L.circle([lat, lng], { radius: accuracy, color: '#1e8fff', fillColor: '#1e8fff', fillOpacity: .08, weight: 1 }).addTo(gpsLayer);
  } else {
    gpsMarker.setLatLng([lat, lng]);
    gpsAccCircle.setLatLng([lat, lng]).setRadius(accuracy);
  }

  headingLayer.clearLayers();
  if (heading != null) {
    const rad = (heading * Math.PI) / 180;
    const len = 0.003;
    const tip = [lat + Math.cos(rad) * len, lng + Math.sin(rad) * len];
    L.polyline([[lat, lng], tip], { color: '#1e8fff', weight: 3, opacity: .8 }).addTo(headingLayer);
  }
}

// ── Waypoints ──────────────────────────────────────────────
let waypoints = loadJSON(STORAGE_KEYS.waypoints, []);

function renderWaypointMarkers() {
  waypointLayer.clearLayers();
  waypoints.forEach((wpt, idx) => {
    const icon = L.divIcon({
      className: '',
      html: `<div class="wpt-marker" title="${escHtml(wpt.name)}">📍</div>`,
      iconSize: [28, 28], iconAnchor: [14, 28]
    });
    L.marker([wpt.lat, wpt.lng], { icon })
      .bindPopup(buildWptPopup(wpt, idx))
      .addTo(waypointLayer);
  });
}

function buildWptPopup(wpt, idx) {
  const dist = state.gps.lat != null ? haversineNm(state.gps.lat, state.gps.lng, wpt.lat, wpt.lng).toFixed(2) + ' nm' : '?';
  return `<b>${escHtml(wpt.name)}</b><br>${fmtCoord(wpt.lat, wpt.lng)}<br>From you: ${dist}<br>
    <a href="#" onclick="navigateTo(${idx});return false">Navigate</a> &nbsp;
    <a href="#" onclick="deleteWaypoint(${idx});return false" style="color:#e63946">Delete</a>`;
}

function enterWaypointMode() {
  state.addingWpt = true;
  map.getContainer().style.cursor = 'crosshair';
  showToast('Tap map to place waypoint');
  btnWaypoint.classList.add('active');
}

function exitWaypointMode() {
  state.addingWpt = false;
  map.getContainer().style.cursor = '';
  btnWaypoint.classList.remove('active');
}

function openWptDialog(latlng) {
  state.pendingWpt = latlng;
  document.getElementById('wpt-coords-display').textContent = fmtCoord(latlng.lat, latlng.lng);
  document.getElementById('wpt-name-input').value = '';
  document.getElementById('wpt-dialog').classList.remove('hidden');
  setTimeout(() => document.getElementById('wpt-name-input').focus(), 100);
}

function saveWaypoint() {
  const name = document.getElementById('wpt-name-input').value.trim() || 'Waypoint ' + (waypoints.length + 1);
  const { lat, lng } = state.pendingWpt;
  waypoints.push({ name, lat, lng, ts: Date.now() });
  saveJSON(STORAGE_KEYS.waypoints, waypoints);
  renderWaypointMarkers();
  renderWaypointsList();
  document.getElementById('wpt-dialog').classList.add('hidden');
  exitWaypointMode();
  showToast(`Saved: ${name}`);
}

window.deleteWaypoint = function(idx) {
  if (!confirm(`Delete "${waypoints[idx].name}"?`)) return;
  map.closePopup();
  waypoints.splice(idx, 1);
  saveJSON(STORAGE_KEYS.waypoints, waypoints);
  renderWaypointMarkers();
  renderWaypointsList();
};

window.navigateTo = function(idx) {
  map.closePopup();
  navigationTarget = waypoints[idx];
  updateNavLine(state.gps.lat, state.gps.lng);
  showToast(`Navigating to ${navigationTarget.name}`);
};

function updateNavLine(lat, lng) {
  if (!navigationTarget || lat == null) return;
  if (navLine) map.removeLayer(navLine);
  navLine = L.polyline([[lat, lng], [navigationTarget.lat, navigationTarget.lng]], {
    color: '#f4a261', weight: 2, dashArray: '6 4', opacity: .85
  }).addTo(map);
}

function renderWaypointsList() {
  const el = document.getElementById('waypoints-list');
  if (!waypoints.length) {
    el.innerHTML = '<p class="empty-msg">No waypoints yet. Tap the Waypoint button then tap the map.</p>';
    return;
  }
  el.innerHTML = waypoints.map((wpt, i) => `
    <div class="wpt-item">
      <div class="wpt-icon">📍</div>
      <div class="wpt-info">
        <div class="wpt-name">${escHtml(wpt.name)}</div>
        <div class="wpt-coords">${fmtCoord(wpt.lat, wpt.lng)}</div>
      </div>
      <div class="wpt-actions">
        <button class="wpt-btn go" onclick="goToWaypoint(${i})">Go</button>
        <button class="wpt-btn del" onclick="deleteWaypoint(${i})">Del</button>
      </div>
    </div>
  `).join('');
}

window.goToWaypoint = function(idx) {
  map.setView([waypoints[idx].lat, waypoints[idx].lng], 15);
  closeAllPanels();
};

// ── Track Recording ────────────────────────────────────────
let savedTracks = loadJSON(STORAGE_KEYS.tracks, []);

function recordTrackPoint(lat, lng) {
  state.track.points.push([lat, lng]);
  if (!activeTrackLine) {
    activeTrackLine = L.polyline([[lat, lng]], { color: '#2dc653', weight: 3, opacity: .85 }).addTo(trackLayer);
  } else {
    activeTrackLine.addLatLng([lat, lng]);
  }
  updateTrackStats();
}

function updateTrackStats() {
  const pts = state.track.points;
  document.getElementById('track-points').textContent = pts.length;
  document.getElementById('track-distance').textContent = totalDistanceNm(pts).toFixed(2);

  const elapsed = state.track.paused
    ? state.track.pauseStart - state.track.startTime - state.track.pauseMs
    : Date.now() - state.track.startTime - state.track.pauseMs;
  document.getElementById('track-duration').textContent = fmtDuration(elapsed);
}

function startTrack() {
  state.track.recording = true;
  state.track.paused    = false;
  state.track.points    = [];
  state.track.startTime = Date.now();
  state.track.pauseMs   = 0;
  if (activeTrackLine) { map.removeLayer(activeTrackLine); activeTrackLine = null; }
  btnTrack.classList.add('recording');
  document.getElementById('btn-track-start').disabled = true;
  document.getElementById('btn-track-pause').disabled = false;
  document.getElementById('btn-track-stop').disabled  = false;
  state.track.interval = setInterval(updateTrackStats, 1000);
  showToast('Track recording started');
}

function pauseTrack() {
  if (state.track.paused) {
    state.track.pauseMs += Date.now() - state.track.pauseStart;
    state.track.paused = false;
    document.getElementById('btn-track-pause').textContent = 'Pause';
    showToast('Track resumed');
  } else {
    state.track.pauseStart = Date.now();
    state.track.paused = true;
    document.getElementById('btn-track-pause').textContent = 'Resume';
    showToast('Track paused');
  }
}

function stopTrack() {
  clearInterval(state.track.interval);
  state.track.recording = false;
  state.track.paused    = false;
  btnTrack.classList.remove('recording');
  document.getElementById('btn-track-start').disabled = false;
  document.getElementById('btn-track-pause').disabled = true;
  document.getElementById('btn-track-stop').disabled  = true;
  document.getElementById('btn-track-pause').textContent = 'Pause';

  const pts = state.track.points;
  if (pts.length < 2) { showToast('Track too short to save'); return; }

  const track = {
    name: 'Track ' + new Date().toLocaleDateString(),
    points: pts,
    distance: totalDistanceNm(pts).toFixed(2),
    duration: fmtDuration(Date.now() - state.track.startTime - state.track.pauseMs),
    ts: Date.now()
  };
  savedTracks.push(track);
  saveJSON(STORAGE_KEYS.tracks, savedTracks);
  renderSavedTracks();
  showToast(`Track saved: ${track.distance} nm`);
}

function renderSavedTracks() {
  const el = document.getElementById('saved-tracks-list');
  if (!savedTracks.length) { el.innerHTML = '<p class="empty-msg">No saved tracks.</p>'; return; }
  el.innerHTML = savedTracks.map((t, i) => `
    <div class="saved-track-item">
      <div>
        <div style="font-weight:600">${escHtml(t.name)}</div>
        <div style="color:var(--text-dim);font-size:11px">${t.distance} nm · ${t.duration}</div>
      </div>
      <div style="display:flex;gap:6px">
        <button class="wpt-btn go" onclick="showSavedTrack(${i})">Show</button>
        <button class="wpt-btn go" onclick="exportTrackGPX(${i})">GPX</button>
        <button class="wpt-btn del" onclick="deleteSavedTrack(${i})">Del</button>
      </div>
    </div>
  `).join('');
}

window.showSavedTrack = function(idx) {
  if (trackPolyline) map.removeLayer(trackPolyline);
  trackPolyline = L.polyline(savedTracks[idx].points, { color: '#f4a261', weight: 2, opacity: .8 }).addTo(trackLayer);
  map.fitBounds(trackPolyline.getBounds(), { padding: [30, 30] });
  closeAllPanels();
};

window.deleteSavedTrack = function(idx) {
  if (!confirm(`Delete "${savedTracks[idx].name}"?`)) return;
  savedTracks.splice(idx, 1);
  saveJSON(STORAGE_KEYS.tracks, savedTracks);
  renderSavedTracks();
};

// ── GPX Export ─────────────────────────────────────────────
function exportWaypointsGPX() {
  if (!waypoints.length) { showToast('No waypoints to export'); return; }
  const wpts = waypoints.map(w =>
    `  <wpt lat="${w.lat}" lon="${w.lng}"><name>${escXml(w.name)}</name><time>${new Date(w.ts).toISOString()}</time></wpt>`
  ).join('\n');
  downloadFile(buildGPX(wpts, ''), `texoma-waypoints-${Date.now()}.gpx`);
}

window.exportTrackGPX = function(idx) {
  const t = savedTracks[idx];
  const trkpts = t.points.map(p => `      <trkpt lat="${p[0]}" lon="${p[1]}"></trkpt>`).join('\n');
  const trk = `  <trk><name>${escXml(t.name)}</name><trkseg>\n${trkpts}\n  </trkseg></trk>`;
  downloadFile(buildGPX('', trk), `texoma-track-${idx}.gpx`);
};

function buildGPX(wptXml, trkXml) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Lake Texoma Nav"
  xmlns="http://www.topografix.com/GPX/1/1">
${wptXml}
${trkXml}
</gpx>`;
}

function downloadFile(content, filename) {
  const a = document.createElement('a');
  a.href = 'data:application/gpx+xml;charset=utf-8,' + encodeURIComponent(content);
  a.download = filename;
  a.click();
}

// ── Offline Tile Caching ───────────────────────────────────
async function cacheTiles() {
  if (!('caches' in window)) { showToast('Cache API not supported'); return; }
  const bounds = map.getBounds();
  const tiles  = [];
  const layers = [TILES.osm, TILES.seamark, TILES.depth];

  for (let z = 10; z <= 16; z++) {
    const nw = latLngToTile(bounds.getNorth(), bounds.getWest(), z);
    const se = latLngToTile(bounds.getSouth(), bounds.getEast(), z);
    for (let x = nw.x; x <= se.x; x++) {
      for (let y = nw.y; y <= se.y; y++) {
        layers.forEach(lyr => {
          const subdomain = ['a','b','c'][Math.abs(x+y) % 3];
          tiles.push(lyr.url.replace('{s}', subdomain).replace('{z}', z).replace('{x}', x).replace('{y}', y));
        });
      }
    }
  }

  const total = tiles.length;
  const progressWrap = document.getElementById('cache-progress-wrap');
  const progressFill = document.getElementById('cache-progress-fill');
  const progressLabel = document.getElementById('cache-progress-label');
  progressWrap.classList.remove('hidden');

  const cache = await caches.open('ltn-tiles-v1');
  let done = 0;
  const batchSize = 8;

  for (let i = 0; i < tiles.length; i += batchSize) {
    const batch = tiles.slice(i, i + batchSize);
    await Promise.allSettled(batch.map(url =>
      cache.match(url).then(hit => hit ? null : fetch(url).then(r => r.ok ? cache.put(url, r) : null).catch(() => null))
    ));
    done = Math.min(i + batchSize, total);
    progressFill.style.width = (done / total * 100) + '%';
    progressLabel.textContent = `${done} / ${total} tiles`;
  }

  showToast(`Cached ${total} tiles for offline use`);
  updateCacheSize();
}

async function clearCache() {
  if (!confirm('Clear all cached tiles?')) return;
  await caches.delete('ltn-tiles-v1');
  showToast('Cache cleared');
  updateCacheSize();
}

async function updateCacheSize() {
  if (!('caches' in window)) return;
  try {
    const cache = await caches.open('ltn-tiles-v1');
    const keys  = await cache.keys();
    document.getElementById('cache-size-label').textContent = `Cached: ${keys.length} tiles`;
  } catch {
    document.getElementById('cache-size-label').textContent = 'Cache: unavailable';
  }
}

function latLngToTile(lat, lng, zoom) {
  const n = Math.pow(2, zoom);
  const x = Math.floor((lng + 180) / 360 * n);
  const latRad = lat * Math.PI / 180;
  const y = Math.floor((1 - Math.log(Math.tan(latRad) + 1 / Math.cos(latRad)) / Math.PI) / 2 * n);
  return { x: Math.max(0, x), y: Math.max(0, y) };
}

// ── Layer Toggle ───────────────────────────────────────────
function setupLayerControls() {
  document.querySelectorAll('input[name="base"]').forEach(radio => {
    radio.addEventListener('change', e => {
      Object.values(baseLayers).forEach(l => map.removeLayer(l));
      baseLayers[e.target.value].addTo(map);
    });
  });
  document.getElementById('layer-depth').addEventListener('change', e => {
    if (e.target.checked) {
      loadDepthContours();
      depthLayer.addTo(map);
      if (map.getZoom() >= 12) soundingLayer.addTo(map);
    } else {
      map.removeLayer(depthLayer);
      map.removeLayer(soundingLayer);
    }
  });
  document.getElementById('layer-seamark').addEventListener('change', e => {
    e.target.checked ? overlayLayers.seamark.addTo(map) : map.removeLayer(overlayLayers.seamark);
  });
  document.getElementById('layer-waypoints').addEventListener('change', e => {
    e.target.checked ? waypointLayer.addTo(map) : map.removeLayer(waypointLayer);
  });
  document.getElementById('layer-track').addEventListener('change', e => {
    e.target.checked ? trackLayer.addTo(map) : map.removeLayer(trackLayer);
  });
}

// ── Panel Management ───────────────────────────────────────
const panels = ['layers-panel', 'waypoints-panel', 'track-panel', 'offline-panel'];

function togglePanel(id) {
  const isOpen = !document.getElementById(id).classList.contains('hidden');
  closeAllPanels();
  if (!isOpen) document.getElementById(id).classList.remove('hidden');
}

function closeAllPanels() {
  panels.forEach(id => document.getElementById(id).classList.add('hidden'));
}

document.querySelectorAll('.panel-close').forEach(btn => {
  btn.addEventListener('click', () => {
    const panelId = btn.dataset.panel;
    document.getElementById(panelId).classList.add('hidden');
  });
});

// ── Button Wiring ──────────────────────────────────────────
const btnFollow   = document.getElementById('btn-follow');
const btnWaypoint = document.getElementById('btn-waypoint');
const btnTrack    = document.getElementById('btn-track');
const btnLayers   = document.getElementById('btn-layers');
const btnOffline  = document.getElementById('btn-offline');

btnFollow.addEventListener('click', () => {
  state.following = !state.following;
  btnFollow.classList.toggle('active', state.following);
  if (state.following && state.gps.lat) map.setView([state.gps.lat, state.gps.lng]);
});

btnWaypoint.addEventListener('click', () => {
  if (state.addingWpt) { exitWaypointMode(); }
  else {
    closeAllPanels();
    enterWaypointMode();
  }
});

btnTrack.addEventListener('click', () => {
  togglePanel('track-panel');
});

btnLayers.addEventListener('click', () => {
  togglePanel('layers-panel');
});

btnOffline.addEventListener('click', () => {
  togglePanel('offline-panel');
  updateCacheSize();
});

document.getElementById('btn-track-start').addEventListener('click', startTrack);
document.getElementById('btn-track-pause').addEventListener('click', pauseTrack);
document.getElementById('btn-track-stop').addEventListener('click', stopTrack);
document.getElementById('btn-cache-tiles').addEventListener('click', cacheTiles);
document.getElementById('btn-clear-cache').addEventListener('click', clearCache);
document.getElementById('btn-export-wpts').addEventListener('click', exportWaypointsGPX);

document.getElementById('wpt-cancel').addEventListener('click', () => {
  document.getElementById('wpt-dialog').classList.add('hidden');
  exitWaypointMode();
});
document.getElementById('wpt-save').addEventListener('click', saveWaypoint);
document.getElementById('wpt-name-input').addEventListener('keydown', e => {
  if (e.key === 'Enter') saveWaypoint();
});

// ── Map Click / Touch ──────────────────────────────────────
map.on('click', e => {
  if (state.addingWpt) {
    openWptDialog(e.latlng);
    return;
  }
  closeAllPanels();
});

map.on('movestart', () => {
  if (state.following && !map._zooming) {
    state.following = false;
    btnFollow.classList.remove('active');
  }
});

// ── Utility ────────────────────────────────────────────────
function haversineNm(lat1, lng1, lat2, lng2) {
  const R = 3440.065; // nautical miles
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat/2)**2 + Math.cos(lat1*Math.PI/180) * Math.cos(lat2*Math.PI/180) * Math.sin(dLng/2)**2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
}

function totalDistanceNm(pts) {
  let d = 0;
  for (let i = 1; i < pts.length; i++) d += haversineNm(pts[i-1][0], pts[i-1][1], pts[i][0], pts[i][1]);
  return d;
}

function fmtCoord(lat, lng) {
  const latDir = lat >= 0 ? 'N' : 'S';
  const lngDir = lng >= 0 ? 'E' : 'W';
  return `${Math.abs(lat).toFixed(5)}°${latDir}  ${Math.abs(lng).toFixed(5)}°${lngDir}`;
}

function fmtDuration(ms) {
  const s = Math.floor(ms / 1000);
  const m = Math.floor(s / 60);
  const h = Math.floor(m / 60);
  return h > 0 ? `${h}:${String(m%60).padStart(2,'0')}:${String(s%60).padStart(2,'0')}` : `${m}:${String(s%60).padStart(2,'0')}`;
}

function escHtml(s) { return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
function escXml(s)  { return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }

function showToast(msg, duration = 2500) {
  const el = document.getElementById('toast');
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(showToast._t);
  showToast._t = setTimeout(() => el.classList.remove('show'), duration);
}

function loadJSON(key, def) {
  try { return JSON.parse(localStorage.getItem(key)) || def; }
  catch { return def; }
}

function saveJSON(key, val) {
  try { localStorage.setItem(key, JSON.stringify(val)); } catch {}
}

// ── Service Worker Registration ────────────────────────────
// Unregister any old service workers so updates always come through immediately
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then(regs => regs.forEach(r => r.unregister()));
}

// ── Boot ───────────────────────────────────────────────────
setupLayerControls();
renderWaypointMarkers();
renderWaypointsList();
renderSavedTracks();
updateCacheSize();
initGPS();

// Auto-load depth chart and check the toggle
document.getElementById('layer-depth').checked = true;
soundingLayer.addTo(map);
loadDepthContours();
