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

    $el.querySelector("button").addEventListener("click", (e) => {
      e.stopPropagation();
      $el.classList.toggle("is-active");
    });

    document.addEventListener("click", () => {
      $el.classList.remove("is-active");
    });
  },
};

export const LocalTime = {
  mounted() {
    this.el.innerText = toLocalTime(this.el.dataset.date);
  },

  updated() {
    this.el.innerText = toLocalTime(this.el.dataset.date);
  },
};

export const LocalDateTime = {
  render() {
    const dateStr = this.el.dataset.date;
    const date = toLocalDate(dateStr, {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
    const time = toLocalTime(dateStr);
    this.el.innerText = `${date}, ${time}`;
  },

  mounted() {
    this.render();
  },

  updated() {
    this.render();
  },
};

export const LocalTimeRange = {
  exec() {
    const date = toLocalDate(this.el.dataset.startDate, {
      year: "numeric",
      month: "short",
      day: "numeric",
    });

    const time = [this.el.dataset.startDate, this.el.dataset.endDate]
      .map((date) =>
        toLocalTime(date, {
          hour: "2-digit",
          minute: "2-digit",
          hour12: false,
        }),
      )
      .join(" – ");

    this.el.innerText = `${date}, ${time}`;
  },

  mounted() {
    this.exec();
  },
  updated() {
    this.exec();
  },
};

export const ConfirmGeoFenceDeletion = {
  mounted() {
    const { id, msg } = this.el.dataset;

    this.el.addEventListener("click", () => {
      if (window.confirm(msg)) {
        this.pushEvent("delete", { id });
      }
    });
  },
};

import {
  Map as M,
  TileLayer,
  LatLng,
  Control,
  Marker,
  Icon,
  Circle,
  CircleMarker,
} from "leaflet";

import markerIcon from "leaflet/dist/images/marker-icon.png";
import markerShadow from "leaflet/dist/images/marker-shadow.png";

const icon = new Icon({
  iconUrl: markerIcon,
  shadowUrl: markerShadow,
  iconAnchor: [12, 40],
  popupAnchor: [0, -25],
});

const DirectionArrow = CircleMarker.extend({
  initialize(latLng, heading, options) {
    this._heading = heading;
    CircleMarker.prototype.initialize.call(this, latLng, {
      fillOpacity: 1,
      radius: 5,
      ...options,
    });
  },

  setHeading(heading) {
    this._heading = heading;
    this.redraw();
  },

  _updatePath() {
    const { x, y } = this._point;

    if (this._heading === "")
      return CircleMarker.prototype._updatePath.call(this);

    this.getElement().setAttributeNS(
      null,
      "transform",
      `translate(${x},${y}) rotate(${this._heading})`,
    );

    const path = this._empty() ? "" : `M0,${3} L-4,${5} L0,${-5} L4,${5} z}`;

    this._renderer._setPath(this, path);
  },
});

function createMap(opts) {
  const map = new M(opts.elId != null ? `map_${opts.elId}` : "map", opts);

  const osm = new TileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19,
  });

  if (opts.enableHybridLayer) {
    const hybrid = new TileLayer(
      "http://{s}.google.com/vt/lyrs=s,h&x={x}&y={y}&z={z}",
      { maxZoom: 20, subdomains: ["mt0", "mt1", "mt2", "mt3"] },
    );

    new Control.Layers({ OSM: osm, Hybrid: hybrid }).addTo(map);
  }

  map.addLayer(osm);

  return map;
}

export const SimpleMap = {
  mounted() {
    const $position = document.querySelector(`#position_${this.el.dataset.id}`);
    const $fullscreenButton = this.el.querySelector(".map-fullscreen-button");
    const $fullscreenIcon = $fullscreenButton
      ? $fullscreenButton.querySelector(".mdi")
      : null;
    this.positionInput = $position;
    this.fullscreenButton = $fullscreenButton;

    const map = createMap({
      elId: this.el.dataset.id,
      zoomControl: !!this.el.dataset.zoom,
      boxZoom: false,
      doubleClickZoom: false,
      keyboard: false,
      scrollWheelZoom: false,
      tap: false,
      dragging: false,
      touchZoom: false,
    });
    this.map = map;

    const isArrow = this.el.dataset.marker === "arrow";
    const [lat, lng, heading] = $position.value.split(",");

    const marker = isArrow
      ? new DirectionArrow([lat, lng], heading)
      : new Marker([lat, lng], { icon });

    const compactZoom = 17;
    map.setView([lat, lng], compactZoom);
    marker.addTo(map);

    const setZoomControlVisible = (visible) => {
      if (map.zoomControl) {
        if (visible) {
          map.addControl(map.zoomControl);
        } else {
          map.removeControl(map.zoomControl);
        }
      }
    };

    setZoomControlVisible(false);

    map.on("mouseover", () => setZoomControlVisible(true));
    map.on("mouseout", () => {
      if (!this.el.classList.contains("is-map-fullscreen")) {
        setZoomControlVisible(false);
      }
    });

    const setInteractive = (enabled) => {
      for (const handler of [
        map.boxZoom,
        map.doubleClickZoom,
        map.dragging,
        map.keyboard,
        map.scrollWheelZoom,
        map.tap,
        map.touchZoom,
      ]) {
        if (handler) {
          enabled ? handler.enable() : handler.disable();
        }
      }
    };

    const invalidateMapSize = (callback) => {
      window.setTimeout(() => {
        map.invalidateSize();
        if (callback) callback();
      }, 0);
    };

    const resetMapView = () => {
      map.setView(marker.getLatLng(), compactZoom, { animate: false });
    };

    const setFullscreenButtonState = (isFullscreen) => {
      const label = isFullscreen
        ? $fullscreenButton.dataset.exitLabel
        : $fullscreenButton.dataset.enterLabel;

      $fullscreenButton.setAttribute("aria-label", label);
      $fullscreenButton.dataset.tooltip = label;
      $fullscreenIcon.classList.toggle("mdi-fullscreen-exit", isFullscreen);
      $fullscreenIcon.classList.toggle("mdi-fullscreen", !isFullscreen);
    };

    const toggleFullscreen = () => {
      const isFullscreen = this.el.classList.toggle("is-map-fullscreen");
      document.documentElement.classList.toggle("is-clipped", isFullscreen);
      setFullscreenButtonState(isFullscreen);
      setZoomControlVisible(isFullscreen);
      setInteractive(isFullscreen);
      invalidateMapSize(isFullscreen ? null : resetMapView);
    };

    if ($fullscreenButton && $fullscreenIcon) {
      $fullscreenButton.dataset.enterLabel =
        $fullscreenButton.getAttribute("aria-label");
      this.handleFullscreenClick = toggleFullscreen;
      this.handleFullscreenKeyup = (e) => {
        if (
          e.key === "Escape" &&
          this.el.classList.contains("is-map-fullscreen")
        ) {
          toggleFullscreen();
        }
      };

      $fullscreenButton.addEventListener("click", this.handleFullscreenClick);
      document.addEventListener("keyup", this.handleFullscreenKeyup);
    }

    if (isArrow) {
      const setView = () => {
        const [lat, lng, heading] = $position.value.split(",");
        marker.setHeading(heading);
        marker.setLatLng([lat, lng]);
        map.setView([lat, lng], map.getZoom());
      };

      this.handlePositionChange = setView;
      $position.addEventListener("change", this.handlePositionChange);
    }
  },

  destroyed() {
    if (this.fullscreenButton && this.handleFullscreenClick) {
      this.fullscreenButton.removeEventListener(
        "click",
        this.handleFullscreenClick,
      );
    }

    if (this.handleFullscreenKeyup) {
      document.removeEventListener("keyup", this.handleFullscreenKeyup);
    }

    if (this.positionInput && this.handlePositionChange) {
      this.positionInput.removeEventListener(
        "change",
        this.handlePositionChange,
      );
    }

    if (this.el.classList.contains("is-map-fullscreen")) {
      document.documentElement.classList.remove("is-clipped");
    }

    if (this.map) {
      this.map.remove();
    }
  },
};

export const TriggerChange = {
  updated() {
    this.el.dispatchEvent(new CustomEvent("change"));
  },
};

import("leaflet-control-geocoder");
import("@geoman-io/leaflet-geoman-free");

export const Map = {
  mounted() {
    const geoFence = (name) =>
      document.querySelector(`input[name='geo_fence[${name}]']`);

    const $radius = geoFence("radius");
    const $latitude = geoFence("latitude");
    const $longitude = geoFence("longitude");

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
      removalMode: false,
    };

    const editOpts = {
      allowSelfIntersection: false,
      preventMarkerRemoval: true,
    };

    const map = createMap({ enableHybridLayer: true });
    map.setView(location, 17, { animate: false });
    map.pm.setLang(LANG);
    map.pm.addControls(controlOpts);
    map.pm.enableGlobalEditMode(editOpts);

    const circle = new Circle(location, { radius: $radius.value })
      .addTo(map)
      .on("pm:edit", (e) => {
        const { lat, lng } = e.target.getLatLng();
        const radius = Math.round(e.target.getRadius());

        $radius.value = radius;
        $latitude.value = lat;
        $longitude.value = lng;

        const mBox = map.getBounds();
        const cBox = circle.getBounds();
        const bounds = mBox.contains(cBox) ? mBox : cBox;
        map.fitBounds(bounds);
      });

    new Control.geocoder({ defaultMarkGeocode: false })
      .on("markgeocode", (e) => {
        const { bbox, center } = e.geocode;

        const poly = L.polygon([
          bbox.getSouthEast(),
          bbox.getNorthEast(),
          bbox.getNorthWest(),
          bbox.getSouthWest(),
        ]);

        circle.setLatLng(center);

        const lBox = poly.getBounds();
        const cBox = circle.getBounds();
        const bounds = cBox.contains(lBox) ? cBox : lBox;

        map.fitBounds(bounds);
        map.pm.enableGlobalEditMode();

        const { lat, lng } = center;
        $latitude.value = lat;
        $longitude.value = lng;
      })
      .addTo(map);

    map.fitBounds(circle.getBounds(), { animate: false });
  },
};

export const Modal = {
  _freeze() {
    document.documentElement.classList.add("is-clipped");
  },

  _unfreeze() {
    document.documentElement.classList.remove("is-clipped");
  },

  mounted() {
    // assumption: 'is-active' is always added after the initial mount
  },

  updated() {
    this.el.classList.contains("is-active") ? this._freeze() : this._unfreeze();
  },

  destroyed() {
    this._unfreeze();
  },
};

export const NumericInput = {
  mounted() {
    this.el.onkeypress = (evt) => {
      const charCode = evt.which ? evt.which : evt.keyCode;
      return !(charCode > 31 && (charCode < 48 || charCode > 57));
    };
  },
};

export const ThemeSelector = {
  mounted() {
    const select = this.el.querySelector("select");
    if (select) {
      select.addEventListener("change", (e) => {
        const themeMode = e.target.value;
        document.documentElement.setAttribute("data-theme-mode", themeMode);

        // Apply theme immediately
        let actualTheme = themeMode;
        if (themeMode === "system") {
          actualTheme = window.matchMedia("(prefers-color-scheme: dark)")
            .matches
            ? "dark"
            : "light";
        }
        document.documentElement.setAttribute("data-theme", actualTheme);
      });
    }
  },
};
