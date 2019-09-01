function dateToLocalTime(dateStr) {
  const date = new Date(dateStr)

  return date instanceof Date && !isNaN(date.valueOf())
    ? date.toLocaleTimeString()
    : '–'
}

export const LocalTime = {
  mounted() {
    this.el.innerText = dateToLocalTime(this.el.dataset.date)
  },

  updated() {
    this.el.innerText = dateToLocalTime(this.el.dataset.date)
  }
}

import 'leaflet-control-geocoder'
import {
  Map as M,
  TileLayer,
  LatLng,
  Control,
  Marker,
  Icon,
  Circle
} from 'leaflet'

function createMap() {
  const map = new M('map')

  const osm = new TileLayer(
    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
    { maxZoom: 19, attribution: 'OSM' }
  )

  map.addLayer(osm)

  return map
}

export const Map = {
  mounted() {
    const $radius = document.querySelector('#geo_fence_radius')
    const $latitude = document.querySelector('#geo_fence_latitude')
    const $longitude = document.querySelector('#geo_fence_longitude')

    let radius = $radius.value
    const location = new LatLng($latitude.value, $longitude.value)

    const map = createMap()
    map.setView(location, 17)

    $radius.addEventListener('input', e => {
      const radius =
        e.target.dataset.unit === 'ft'
          ? e.target.value / 3.28084
          : e.target.value

      circle.setRadius(radius)

      return true
    })

    const icon = new Icon({
      iconUrl: require('leaflet/dist/images/marker-icon.png'),
      shadowUrl: require('leaflet/dist/images/marker-shadow.png'),
      iconAnchor: [12, 40],
      popupAnchor: [0, -25]
    })

    const circle = new Circle(location, { radius }).addTo(map)

    const editable = this.el.dataset.editable == 'true'

    const marker = new Marker(location, { icon, draggable: editable })
      .addTo(map)
      .on('dragstart', () => circle.setStyle({ opacity: 0, fill: false }))
      .on('dragend', e => {
        const { lat, lng } = marker.getLatLng()

        $latitude.value = lat
        $longitude.value = lng

        circle.setLatLng(marker.getLatLng())
        circle.setStyle({ opacity: 1, fill: true })
      })

    if (editable) {
      new Control.geocoder({ defaultMarkGeocode: false })
        .on('markgeocode', function(e) {
          console.log(e)
          const bbox = e.geocode.bbox

          const poly = L.polygon([
            bbox.getSouthEast(),
            bbox.getNorthEast(),
            bbox.getNorthWest(),
            bbox.getSouthWest()
          ])

          map.fitBounds(poly.getBounds())

          marker.setLatLng(e.geocode.center)
          circle.setLatLng(e.geocode.center)
        })
        .addTo(map)
    }
  }
}
