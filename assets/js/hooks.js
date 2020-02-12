const LANG = navigator.languages
  ? navigator.languages[0]
  : navigator.language || navigator.userLanguage;

function toLocalTime(dateStr, opts) {
  const date = new Date(dateStr);

  return date instanceof Date && !isNaN(date.valueOf())
    ? date.toLocaleTimeString(LANG, opts)
    : "–";
}

function toLocalDate(dateStr, opts) {
  const date = new Date(dateStr);

  return date instanceof Date && !isNaN(date.valueOf())
    ? date.toLocaleDateString(LANG, opts)
    : "–";
}

export const Dropdown = {
  mounted() {
    const $el = this.el;

    $el.querySelector("button").addEventListener("click", e => {
      e.stopPropagation();
      $el.classList.toggle("is-active");
    });

    document.addEventListener("click", () => {
      $el.classList.remove("is-active");
    });
  }
};

export const LocalTime = {
  mounted() {
    this.el.innerText = toLocalTime(this.el.dataset.date);
  },

  updated() {
    this.el.innerText = toLocalTime(this.el.dataset.date);
  }
};

export const LocalTimeRange = {
  exec() {
    const date = toLocalDate(this.el.dataset.startDate, {
      year: "numeric",
      month: "short",
      day: "numeric"
    });

    const time = [this.el.dataset.startDate, this.el.dataset.endDate]
      .map(date =>
        toLocalTime(date, { hour: "2-digit", minute: "2-digit", hour12: false })
      )
      .join(" – ");

    this.el.innerText = `${date}, ${time}`;
  },

  mounted() {
    this.exec();
  },
  updated() {
    this.exec();
  }
};

export const ConfirmGeoFenceDeletion = {
  mounted() {
    const { id, msg } = this.el.dataset;

    this.el.addEventListener("click", () => {
      if (window.confirm(msg)) {
        this.pushEvent("delete", { id });
      }
    });
  }
};

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
  const map = new M(opts.elId != null ? `map_${opts.elId}` : "map", opts);

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
    const $position = document.querySelector(`#position_${this.el.dataset.id}`);

    const map = createMap({
      elId: this.el.dataset.id,
      zoomControl: !!this.el.dataset.zoom,
      dragging: false,
      boxZoom: false,
      doubleClickZoom: false,
      keyboard: false,
      scrollWheelZoom: false,
      tap: false,
      dragging: false,
      touchZoom: false
    });

    let marker;
    const setView = () => {
      if (marker) map.removeLayer(marker);
      const [lat, lng] = $position.value.split(",");
      const location = new LatLng(lat, lng);
      map.setView(location, 17);
      marker = new Marker(location, { icon }).addTo(map);
    };

    setView();

    $position.addEventListener("change", setView);
  }
};

export const TriggerChange = {
  updated() {
    this.el.dispatchEvent(new CustomEvent("change"));
  }
};

export const Map = {
  mounted() {
    Promise.all([
      import(
        /* webpackPreload: true, webpackChunkName: "geo" */ "leaflet-control-geocoder"
      ),
      import(
        /* webpackPreload: true, webpackChunkName: "geo" */ "@geoman-io/leaflet-geoman-free"
      )
    ]).then(() => {
      const $radius = document.querySelector("#geo_fence_radius");
      const $latitude = document.querySelector("#geo_fence_latitude");
      const $longitude = document.querySelector("#geo_fence_longitude");

      const location = new LatLng($latitude.value, $longitude.value);

      const controlOpts = {
        position: "topleft",
        cutPolygon: false,
        drawCircle: false,
        drawCircleMarker: false,
        drawMarker: false,
        drawPolygon: false,
        drawPolyline: false,
        drawRectangle: false,
        removalMode: false
      };

      const editOpts = {
        allowSelfIntersection: false,
        preventMarkerRemoval: true
      };

      const map = createMap({ enableHybridLayer: true });
      map.setView(location, 17, { animate: false });
      map.pm.setLang(LANG);
      map.pm.addControls(controlOpts);
      map.pm.enableGlobalEditMode(editOpts);

      const circle = new Circle(location, { radius: $radius.value })
        .addTo(map)
        .on("pm:edit", e => {
          const { lat, lng } = e.target.getLatLng();
          const radius = Math.round(e.target.getRadius());

          $radius.value = radius;
          $latitude.value = lat;
          $longitude.value = lng;

          const mBox = map.getBounds();
          const cBox = circle.getBounds();
          const bounds = mBox.contains(cBox) ? mBox : cBox;
          map.fitBounds(bounds);

          this._push({ lat, lng, radius });
        });

      new Control.geocoder({ defaultMarkGeocode: false })
        .on("markgeocode", e => {
          const { bbox, center } = e.geocode;

          const poly = L.polygon([
            bbox.getSouthEast(),
            bbox.getNorthEast(),
            bbox.getNorthWest(),
            bbox.getSouthWest()
          ]);

          circle.setLatLng(center);

          const lBox = poly.getBounds();
          const cBox = circle.getBounds();
          const bounds = cBox.contains(lBox) ? cBox : lBox;

          map.fitBounds(bounds);
          map.pm.enableGlobalEditMode();

          const { lat, lng } = center;
          const radius = Math.round(circle.getRadius());

          $latitude.value = lat;
          $longitude.value = lng;

          this._push({ lat, lng, radius });
        })
        .addTo(map);

      map.fitBounds(circle.getBounds(), { animate: false });
    });
  },

  _push({ lat: latitude, lng: longitude, radius }) {
    this.pushEvent("validate", { geo_fence: { latitude, longitude, radius } });
  }
};

export const SetLangAttr = {
  exec() {
    this.el.setAttribute("lang", LANG);
  },

  mounted() {
    this.exec();
  },
  updated() {
    this.exec();
  }
};
