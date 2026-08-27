defmodule TeslaMate.Locations.GeocoderTest do
  use ExUnit.Case, async: false

  alias TeslaMate.Locations.Geocoder

  import Mock

  defp geocoder_mock(lat, lon, body) do
    {Tesla.Adapter.Finch, [],
     call: fn %Tesla.Env{} = env, _opts ->
       assert env.url == "https://nominatim.openstreetmap.org/reverse"

       assert env.query == [
                {:format, :jsonv2},
                {:addressdetails, 1},
                {:extratags, 1},
                {:namedetails, 1},
                {:zoom, 19},
                {:lat, lat},
                {:lon, lon}
              ]

       env = %Tesla.Env{
         body: body,
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
         status: 200
       }

       {:ok, env}
     end}
  end

  test "does a reverse lookup of the given coordinates" do
    with_mocks [
      geocoder_mock(37.889602, 41.129182, %{
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
        "licence" => "Data © OpenStreetMap contributors, ODbL 1.0. https://osm.org/copyright",
        "lon" => "41.1288167",
        "name" => "Kahve Deryası",
        "namedetails" => %{"name" => "Kahve Deryası"},
        "osm_id" => 5_983_038_298,
        "osm_type" => "node",
        "place_id" => 241_575_531,
        "place_rank" => 30,
        "type" => "cafe"
      })
    ] do
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

  test "resolves the state for an Australian territory" do
    with_mocks [
      geocoder_mock(-35.1604, 149.1049, %{
        "address" => %{
          "road" => "Burrumarra Avenue",
          "suburb" => "Ngunnawal",
          "town" => "District of Gungahlin",
          "territory" => "Australian Capital Territory",
          "ISO3166-2-lvl4" => "AU-ACT",
          "postcode" => "2913",
          "country" => "Australia",
          "country_code" => "au"
        },
        "addresstype" => "road",
        "boundingbox" => ["-35.1605549", "-35.1598870", "149.1032096", "149.1053282"],
        "category" => "highway",
        "display_name" =>
          "Burrumarra Avenue, Ngunnawal, District of Gungahlin, Australian Capital Territory, 2913, Australia",
        "extratags" => %{
          "lit" => "yes",
          "lanes" => "2",
          "surface" => "paved",
          "cycleway" => "lane",
          "maxspeed" => "50",
          "lanes:forward" => "1",
          "maxspeed:type" => "sign",
          "lanes:backward" => "1"
        },
        "importance" => 0.05340591515983822,
        "lat" => "-35.1603719",
        "licence" => "Data © OpenStreetMap contributors, ODbL 1.0. https://osm.org/copyright",
        "lon" => "149.1049118",
        "name" => "Burrumarra Avenue",
        "namedetails" => %{"name" => "Burrumarra Avenue"},
        "osm_id" => 263_936_866,
        "osm_type" => "way",
        "place_id" => 24_024_293,
        "place_rank" => 26,
        "type" => "tertiary"
      })
    ] do
      assert Geocoder.reverse_lookup(-35.1604, 149.1049) ==
               {:ok,
                %{
                  city: "District of Gungahlin",
                  country: "Australia",
                  county: nil,
                  display_name:
                    "Burrumarra Avenue, Ngunnawal, District of Gungahlin, Australian Capital Territory, 2913, Australia",
                  house_number: nil,
                  latitude: "-35.1603719",
                  longitude: "149.1049118",
                  name: "Burrumarra Avenue",
                  neighbourhood: "Ngunnawal",
                  osm_id: 263_936_866,
                  osm_type: "way",
                  postcode: "2913",
                  road: "Burrumarra Avenue",
                  state: "Australian Capital Territory",
                  state_district: nil,
                  raw: %{
                    "address" => %{
                      "road" => "Burrumarra Avenue",
                      "suburb" => "Ngunnawal",
                      "town" => "District of Gungahlin",
                      "territory" => "Australian Capital Territory",
                      "ISO3166-2-lvl4" => "AU-ACT",
                      "postcode" => "2913",
                      "country" => "Australia",
                      "country_code" => "au"
                    },
                    "addresstype" => "road",
                    "boundingbox" => ["-35.1605549", "-35.1598870", "149.1032096", "149.1053282"],
                    "category" => "highway",
                    "display_name" =>
                      "Burrumarra Avenue, Ngunnawal, District of Gungahlin, Australian Capital Territory, 2913, Australia",
                    "extratags" => %{
                      "lit" => "yes",
                      "lanes" => "2",
                      "surface" => "paved",
                      "cycleway" => "lane",
                      "maxspeed" => "50",
                      "lanes:forward" => "1",
                      "maxspeed:type" => "sign",
                      "lanes:backward" => "1"
                    },
                    "importance" => 0.05340591515983822,
                    "lat" => "-35.1603719",
                    "licence" =>
                      "Data © OpenStreetMap contributors, ODbL 1.0. https://osm.org/copyright",
                    "lon" => "149.1049118",
                    "name" => "Burrumarra Avenue",
                    "namedetails" => %{"name" => "Burrumarra Avenue"},
                    "osm_id" => 263_936_866,
                    "osm_type" => "way",
                    "place_id" => 24_024_293,
                    "place_rank" => 26,
                    "type" => "tertiary"
                  }
                }}
    end
  end

  test "returns a dummy address if the location cannot be geocoded" do
    with_mock Tesla.Adapter.Finch,
      call: fn %Tesla.Env{} = env, _opts ->
        assert env.url == "https://nominatim.openstreetmap.org/reverse"

        assert env.query == [
                 format: :jsonv2,
                 addressdetails: 1,
                 extratags: 1,
                 namedetails: 1,
                 zoom: 19,
                 lat: 37.889602,
                 lon: 41.129182
               ]

        {:ok, %Tesla.Env{body: %{"error" => "Unable to geocode"}, headers: [], status: 200}}
      end do
      assert Geocoder.reverse_lookup(37.889602, 41.129182) ==
               {:ok,
                %{
                  display_name: "Unknown",
                  raw: %{"error" => "Unable to geocode"},
                  latitude: 0.0,
                  longitude: 0.0,
                  osm_id: 0,
                  osm_type: "unknown"
                }}
    end
  end

  test "handles errors" do
    with_mock Tesla.Adapter.Finch,
      call: fn
        %Tesla.Env{} = env, _opts ->
          assert env.url == "https://nominatim.openstreetmap.org/reverse"

          assert env.query == [
                   format: :jsonv2,
                   addressdetails: 1,
                   extratags: 1,
                   namedetails: 1,
                   zoom: 19,
                   lat: 37.889602,
                   lon: 41.129182
                 ]

          {:ok, %Tesla.Env{body: %{"error" => "failure"}, headers: [], status: 200}}
      end do
      assert Geocoder.reverse_lookup(37.889602, 41.129182) ==
               {:error, {:geocoding_failed, "failure"}}
    end
  end

  describe "address formatting" do
    test "village aliases are ranked higher than municipality aliases" do
      with_mocks [
        geocoder_mock(46.2806871, 6.0134696, %{
          "address" => %{
            "country" => "France",
            "country_code" => "fr",
            "county" => "Loire",
            "municipality" => "Montbrison",
            "postcode" => "42130",
            "road" => "Avenue des Bourgs",
            "state" => "Auvergne-Rhône-Alpes",
            "village" => "Sainte-Agathe-la-Bouteresse"
          },
          "addresstype" => "road",
          "boundingbox" => ["45.7342628", "45.7370163", "4.0417286", "4.0555069"],
          "category" => "highway",
          "display_name" =>
            "Avenue des Bourgs, Sainte-Agathe-la-Bouteresse, Montbrison, Loire, Auvergne-Rhône-Alpes, Metropolitan France, 42130, France",
          "extratags" => %{},
          "importance" => 0.09999999999999998,
          "lat" => "45.734272456977024",
          "licence" => "Data © OpenStreetMap contributors, ODbL 1.0. https://osm.org/copyright",
          "lon" => "4.055428979909518",
          "name" => "Avenue des Bourgs",
          "namedetails" => %{"name" => "Avenue des Bourgs"},
          "osm_id" => 192_323_453,
          "osm_type" => "way",
          "place_id" => 136_861_009,
          "place_rank" => 26,
          "type" => "unclassified"
        })
      ] do
        assert {:ok,
                %{
                  city: "Sainte-Agathe-la-Bouteresse",
                  country: "France",
                  county: "Loire",
                  display_name:
                    "Avenue des Bourgs, Sainte-Agathe-la-Bouteresse, Montbrison, Loire, Auvergne-Rhône-Alpes, Metropolitan France, 42130, France",
                  house_number: nil,
                  name: "Avenue des Bourgs",
                  neighbourhood: nil,
                  postcode: "42130",
                  road: "Avenue des Bourgs",
                  state: "Auvergne-Rhône-Alpes",
                  state_district: nil
                }} = Geocoder.reverse_lookup(46.2806871, 6.0134696)
      end
    end
  end
end
