import L from "leaflet";
import "leaflet/dist/leaflet.css";

const TILES = "https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png";

export function mountMap(element, trek) {
  const centerLat = trek.stops.reduce((sum, stop) => sum + stop.lat, 0) / trek.stops.length;
  const centerLng = trek.stops.reduce((sum, stop) => sum + stop.lng, 0) / trek.stops.length;
  const map = L.map(element, {
    zoomControl: false,
    attributionControl: true,
  }).setView([centerLat, centerLng], 13);

  L.tileLayer(TILES, {
    maxZoom: 19,
    attribution: '&copy; OpenStreetMap &copy; CARTO',
  }).addTo(map);

  L.control.zoom({ position: "topright" }).addTo(map);

  const markers = new Map();
  const circles = new Map();
  for (const stop of trek.stops) {
    const icon = L.divIcon({
      className: "pin",
      html: `<span><b>${trek.stops.indexOf(stop) + 1}</b></span>`,
      iconSize: [36, 36],
      iconAnchor: [18, 18],
    });
    markers.set(stop.id, L.marker([stop.lat, stop.lng], { icon, title: stop.name }).addTo(map));
    circles.set(
      stop.id,
      L.circle([stop.lat, stop.lng], {
        radius: trek.radiusMeters,
        color: "#a15c12",
        weight: 1.5,
        fillColor: "#e2a53a",
        fillOpacity: 0.12,
      }).addTo(map),
    );
  }

  const user = L.circleMarker([centerLat, centerLng], {
    radius: 8,
    color: "#143d32",
    weight: 2,
    fillColor: "#1f6b4a",
    fillOpacity: 0.95,
  });

  return {
    map,
    setUser(latlng) {
      if (!map.hasLayer(user)) user.addTo(map);
      user.setLatLng([latlng.lat, latlng.lng]);
    },
    setCollected(collected) {
      for (const stop of trek.stops) {
        const marker = markers.get(stop.id);
        const done = Boolean(collected[stop.id]);
        marker.setOpacity(done ? 0.45 : 1);
        const icon = marker.getElement();
        if (icon) icon.classList.toggle("done", done);
      }
    },
    invalidate() {
      map.invalidateSize();
    },
  };
}
