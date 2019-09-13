function dateToLocalTime(dateStr) {
  const date = new Date(dateStr);

  return date instanceof Date && !isNaN(date.valueOf())
    ? date.toLocaleTimeString()
    : "–";
}

export const LocalTime = {
  mounted() {
    this.el.innerText = dateToLocalTime(this.el.dataset.date);
  },

  updated() {
    this.el.innerText = dateToLocalTime(this.el.dataset.date);
  }
};

import "leaflet-control-geocoder";
import {
  Map as M,
  TileLayer,
  LatLng,
  Control,
  Marker,
  Icon,
  Circle
} from "leaflet";

const icon = new Icon({
  iconUrl: require("leaflet/dist/images/marker-icon.png"),
  shadowUrl: require("leaflet/dist/images/marker-shadow.png"),
  iconAnchor: [12, 40],
  popupAnchor: [0, -25]
});

function createMap(opts) {
  const map = new M("map", opts);

  const osm = new TileLayer(
    "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
    { maxZoom: 19 }
  );

  if (opts.enableHybridLayer) {
    const hybrid = new TileLayer(
      "http://{s}.google.com/vt/lyrs=s,h&x={x}&y={y}&z={z}",
      { maxZoom: 20, subdomains: ["mt0", "mt1", "mt2", "mt3"] }
    );

    new Control.Layers({ OSM: osm, Hybrid: hybrid }).addTo(map);
  }

  map.addLayer(osm);

  return map;
}

export const SimpleMap = {
  mounted() {
    const $position = this.el.parentElement.querySelector(".position");

    let marker;
    const setView = () => {
      if (marker) map.removeLayer(marker);
      const [lat, lng] = $position.value.split(",");
      const location = new LatLng(lat, lng);
      map.setView(location, 17);
      marker = new Marker(location, { icon }).addTo(map);
    };

    const map = createMap({
      zoomControl: false,
      dragging: false,
      boxZoom: false,
      doubleClickZoom: false,
      keyboard: false,
      scrollWheelZoom: false,
      tap: false
    });
    $position.addEventListener("change", setView);
    setView();
  }
};

export const TriggerChange = {
  updated() {
    this.el.dispatchEvent(new CustomEvent("change", {}));
  }
};

export const Map = {
  mounted() {
    const $radius = document.querySelector("#geo_fence_radius");
    const $latitude = document.querySelector("#geo_fence_latitude");
    const $longitude = document.querySelector("#geo_fence_longitude");

    let radius = $radius.value;
    const location = new LatLng($latitude.value, $longitude.value);

    const map = createMap({ enableHybridLayer: true });
    map.setView(location, 17);

    $radius.addEventListener("input", e => {
      const radius =
        e.target.dataset.unit === "ft"
          ? e.target.value / 3.28084
          : e.target.value;

      circle.setRadius(radius);

      return true;
    });

    const circle = new Circle(location, { radius }).addTo(map);

    const editable = this.el.dataset.editable == "true";

    const marker = new Marker(location, { icon, draggable: editable })
      .addTo(map)
      .on("dragstart", () => circle.setStyle({ opacity: 0, fill: false }))
      .on("dragend", e => {
        const { lat, lng } = marker.getLatLng();

        $latitude.value = lat;
        $longitude.value = lng;

        circle.setLatLng(marker.getLatLng());
        circle.setStyle({ opacity: 1, fill: true });
      });

    if (editable) {
      new Control.geocoder({ defaultMarkGeocode: false })
        .on("markgeocode", function(e) {
          console.log(e);
          const bbox = e.geocode.bbox;

          const poly = L.polygon([
            bbox.getSouthEast(),
            bbox.getNorthEast(),
            bbox.getNorthWest(),
            bbox.getSouthWest()
          ]);

          map.fitBounds(poly.getBounds());

          marker.setLatLng(e.geocode.center);
          circle.setLatLng(e.geocode.center);
        })
        .addTo(map);
    }
  }
};
