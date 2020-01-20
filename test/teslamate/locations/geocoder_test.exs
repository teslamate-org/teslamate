defmodule TeslaMate.Locations.GeocoderTest do
  use ExUnit.Case, async: false

  alias TeslaMate.Locations.Geocoder

  import Mock

  @response {:ok,
             %Mojito.Response{
               body:
                 "{\"place_id\":241575531,\"licence\":\"Data © OpenStreetMap contributors, ODbL 1.0. https://osm.org/copyright\",\"osm_type\":\"node\",\"osm_id\":5983038298,\"lat\":\"37.8895442\",\"lon\":\"41.1288167\",\"place_rank\":30,\"category\":\"amenity\",\"type\":\"cafe\",\"importance\":0,\"addresstype\":\"amenity\",\"name\":\"Kahve Deryası\",\"display_name\":\"Kahve Deryası, Cihan Kavşağı, Batman, Ziyagökalp Mahallesi, Batman merkez, Batman, Southeastern Anatolia Region, 72060, Turkey\",\"address\":{\"cafe\":\"Kahve Deryası\",\"road\":\"Cihan Kavşağı\",\"residential\":\"Batman\",\"suburb\":\"Ziyagökalp Mahallesi\",\"city\":\"Batman merkez\",\"state\":\"Southeastern Anatolia Region\",\"postcode\":\"72060\",\"country\":\"Turkey\",\"country_code\":\"tr\"},\"extratags\":{},\"namedetails\":{\"name\":\"Kahve Deryası\"},\"boundingbox\":[\"37.8894442\",\"37.8896442\",\"41.1287167\",\"41.1289167\"]}",
               complete: true,
               headers: [
                 {"date", "Sun, 01 Sep 2019 21:03:23 GMT"},
                 {"server", "Apache/2.4.29 (Ubuntu)"},
                 {"access-control-allow-origin", "*"},
                 {"access-control-allow-methods", "OPTIONS,GET"},
                 {"strict-transport-security", "max-age=31536000; includeSubDomains; preload"},
                 {"expect-ct",
                  "max-age=0, report-uri=\"https://openstreetmap.report-uri.com/r/d/ct/reportOnly\""},
                 {"content-type", "application/json; charset=UTF-8"}
               ],
               status_code: 200
             }}

  test "geocoders coordinates" do
    with_mock Mojito,
      get:
        fn "https://nominatim.openstreetmap.org/reverse?format=jsonv2&addressdetails=1&extratags=1&namedetails=1&zoom=19&lat=37.889602&lon=41.129182",
           _headers ->
          @response
        end do
      assert Geocoder.reverse_lookup(37.889602, 41.129182) ==
               {:ok,
                %{
                  city: "Batman merkez",
                  country: "Turkey",
                  county: nil,
                  display_name:
                    "Kahve Deryası, Cihan Kavşağı, Batman, Ziyagökalp Mahallesi, Batman merkez, Batman, Southeastern Anatolia Region, 72060, Turkey",
                  house_number: nil,
                  latitude: "37.8895442",
                  longitude: "41.1288167",
                  name: "Kahve Deryası",
                  neighbourhood: "Ziyagökalp Mahallesi",
                  osm_id: 5_983_038_298,
                  osm_type: "node",
                  postcode: "72060",
                  road: "Cihan Kavşağı",
                  state: "Southeastern Anatolia Region",
                  state_district: nil,
                  raw: %{
                    "address" => %{
                      "cafe" => "Kahve Deryası",
                      "city" => "Batman merkez",
                      "country" => "Turkey",
                      "country_code" => "tr",
                      "postcode" => "72060",
                      "residential" => "Batman",
                      "road" => "Cihan Kavşağı",
                      "state" => "Southeastern Anatolia Region",
                      "suburb" => "Ziyagökalp Mahallesi"
                    },
                    "addresstype" => "amenity",
                    "boundingbox" => ["37.8894442", "37.8896442", "41.1287167", "41.1289167"],
                    "category" => "amenity",
                    "display_name" =>
                      "Kahve Deryası, Cihan Kavşağı, Batman, Ziyagökalp Mahallesi, Batman merkez, Batman, Southeastern Anatolia Region, 72060, Turkey",
                    "extratags" => %{},
                    "importance" => 0,
                    "lat" => "37.8895442",
                    "licence" =>
                      "Data © OpenStreetMap contributors, ODbL 1.0. https://osm.org/copyright",
                    "lon" => "41.1288167",
                    "name" => "Kahve Deryası",
                    "namedetails" => %{"name" => "Kahve Deryası"},
                    "osm_id" => 5_983_038_298,
                    "osm_type" => "node",
                    "place_id" => 241_575_531,
                    "place_rank" => 30,
                    "type" => "cafe"
                  }
                }}
    end
  end
end
