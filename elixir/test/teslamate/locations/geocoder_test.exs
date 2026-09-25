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

  describe "address fields" do
    # Which address label of the Nominatim response fills which field, in
    # order of precedence: the first label of a list that the response
    # contains wins.
    @fields [
      house_number: ~w(house_number),
      road:
        ~w(road pedestrian footway path isolated_dwelling farm city_block mountain_pass square locality),
      neighbourhood:
        ~w(neighbourhood subdivision quarter suburb hamlet croft borough city_district residential farmyard industrial commercial allotments retail),
      city: ~w(city town village municipality),
      county: ~w(county district),
      state: ~w(state province territory),
      country: ~w(country)
    ]

    @field_names Keyword.keys(@fields)

    # Address parts of real reverse lookups on nominatim.openstreetmap.org
    # (September 2026, parameters of reverse_lookup/3, Accept-Language: en),
    # limited to the labels above: 92 address parts, an insubstantial extract
    # under the ODbL (fewer than 100 features, OSMF Substantial Guideline).
    @recorded [
      {"Beijing, Chaoyang",
       %{"city" => "Chaoyang District", "country" => "China", "suburb" => "Chaowai Subdistrict"},
       %{
         state: nil,
         house_number: nil,
         road: nil,
         neighbourhood: "Chaowai Subdistrict",
         city: "Chaoyang District",
         county: nil,
         country: "China"
       }},
      {"Shanghai, Pudong",
       %{
         "city" => "Pudong",
         "country" => "China",
         "quarter" => "Lujiazui",
         "road" => "银城中路出口",
         "state" => "Shanghai",
         "suburb" => "Lujiazui Subdistrict"
       },
       %{
         state: "Shanghai",
         house_number: nil,
         road: "银城中路出口",
         neighbourhood: "Lujiazui",
         city: "Pudong",
         county: nil,
         country: "China"
       }},
      {"Shenzhen, Nanshan",
       %{
         "city" => "Nanshan District",
         "commercial" => "麻雀岭工业区",
         "country" => "China",
         "house_number" => "1",
         "neighbourhood" => "Maling",
         "road" => "科艺路",
         "state" => "Guangdong",
         "suburb" => "Yuehai Sub-district"
       },
       %{
         state: "Guangdong",
         house_number: "1",
         road: "科艺路",
         neighbourhood: "Maling",
         city: "Nanshan District",
         county: nil,
         country: "China"
       }},
      {"Zhejiang, Anji County",
       %{
         "city" => "Anji County",
         "country" => "China",
         "state" => "Zhejiang",
         "suburb" => "Changshuo"
       },
       %{
         state: "Zhejiang",
         house_number: nil,
         road: nil,
         neighbourhood: "Changshuo",
         city: "Anji County",
         county: nil,
         country: "China"
       }},
      {"New York, Manhattan",
       %{
         "city" => "New York",
         "city_district" => "New York County",
         "commercial" => "Times Square",
         "country" => "United States",
         "neighbourhood" => "Manhattan Community Board 5",
         "road" => "7th Avenue",
         "state" => "New York",
         "suburb" => "Manhattan"
       },
       %{
         state: "New York",
         house_number: nil,
         road: "7th Avenue",
         neighbourhood: "Manhattan Community Board 5",
         city: "New York",
         county: nil,
         country: "United States"
       }},
      {"Palo Alto, California",
       %{
         "city" => "Palo Alto",
         "country" => "United States",
         "county" => "Santa Clara County",
         "road" => "Middlefield Road",
         "state" => "California"
       },
       %{
         state: "California",
         house_number: nil,
         road: "Middlefield Road",
         neighbourhood: nil,
         city: "Palo Alto",
         county: "Santa Clara County",
         country: "United States"
       }},
      {"Lancaster, Pennsylvania",
       %{
         "city" => "Lancaster",
         "country" => "United States",
         "county" => "Lancaster County",
         "neighbourhood" => "Central Business District",
         "road" => "East King Street",
         "state" => "Pennsylvania"
       },
       %{
         state: "Pennsylvania",
         house_number: nil,
         road: "East King Street",
         neighbourhood: "Central Business District",
         city: "Lancaster",
         county: "Lancaster County",
         country: "United States"
       }},
      {"West Kill, New York",
       %{
         "country" => "United States",
         "county" => "Greene County",
         "hamlet" => "West Kill",
         "road" => "State Route 42",
         "state" => "New York",
         "village" => "Town of Lexington"
       },
       %{
         state: "New York",
         house_number: nil,
         road: "State Route 42",
         neighbourhood: "West Kill",
         city: "Town of Lexington",
         county: "Greene County",
         country: "United States"
       }},
      {"Austin, Texas",
       %{
         "city" => "Austin",
         "country" => "United States",
         "county" => "Travis County",
         "house_number" => "1",
         "road" => "Tesla Road",
         "state" => "Texas"
       },
       %{
         state: "Texas",
         house_number: "1",
         road: "Tesla Road",
         neighbourhood: nil,
         city: "Austin",
         county: "Travis County",
         country: "United States"
       }},
      {"Sydney",
       %{
         "city" => "Sydney",
         "country" => "Australia",
         "house_number" => "25",
         "neighbourhood" => "Wynyard",
         "road" => "Martin Place",
         "state" => "New South Wales",
         "suburb" => "Sydney"
       },
       %{
         state: "New South Wales",
         house_number: "25",
         road: "Martin Place",
         neighbourhood: "Wynyard",
         city: "Sydney",
         county: nil,
         country: "Australia"
       }},
      {"Melbourne, Prahran",
       %{
         "city" => "Melbourne",
         "country" => "Australia",
         "house_number" => "14",
         "road" => "Errol Street",
         "state" => "Victoria",
         "suburb" => "Prahran"
       },
       %{
         state: "Victoria",
         house_number: "14",
         road: "Errol Street",
         neighbourhood: "Prahran",
         city: "Melbourne",
         county: nil,
         country: "Australia"
       }},
      {"Darwin, Northern Territory",
       %{
         "city" => "Darwin",
         "city_district" => "Darwin City",
         "country" => "Australia",
         "road" => "Bennett Street",
         "suburb" => "Darwin City",
         "territory" => "Northern Territory"
       },
       %{
         state: "Northern Territory",
         house_number: nil,
         road: "Bennett Street",
         neighbourhood: "Darwin City",
         city: "Darwin",
         county: nil,
         country: "Australia"
       }},
      {"Belli Park, Queensland",
       %{
         "city_district" => "Belli Park",
         "country" => "Australia",
         "road" => "Ford Break",
         "state" => "Queensland"
       },
       %{
         state: "Queensland",
         house_number: nil,
         road: "Ford Break",
         neighbourhood: "Belli Park",
         city: nil,
         county: nil,
         country: "Australia"
       }},
      {"Berlin, Mitte",
       %{
         "borough" => "Mitte",
         "city" => "Berlin",
         "country" => "Germany",
         "neighbourhood" => "Nikolaiviertel",
         "quarter" => "Spandauer Vorstadt",
         "road" => "Spandauer Straße",
         "suburb" => "Mitte"
       },
       %{
         state: nil,
         house_number: nil,
         road: "Spandauer Straße",
         neighbourhood: "Nikolaiviertel",
         city: "Berlin",
         county: nil,
         country: "Germany"
       }},
      {"Kelheim, Bavaria",
       %{
         "country" => "Germany",
         "county" => "Landkreis Kelheim",
         "road" => "Giselastraße",
         "state" => "Bavaria",
         "suburb" => "Affecking",
         "town" => "Kelheim"
       },
       %{
         state: "Bavaria",
         house_number: nil,
         road: "Giselastraße",
         neighbourhood: "Affecking",
         city: "Kelheim",
         county: "Landkreis Kelheim",
         country: "Germany"
       }},
      {"Oslo",
       %{
         "city" => "Oslo",
         "city_district" => "Oslo",
         "country" => "Norway",
         "neighbourhood" => "Sjøtomta",
         "quarter" => "Vaterland",
         "road" => "Storgata",
         "suburb" => "Sentrum"
       },
       %{
         state: nil,
         house_number: nil,
         road: "Storgata",
         neighbourhood: "Sjøtomta",
         city: "Oslo",
         county: nil,
         country: "Norway"
       }},
      {"Lillehammer, Innlandet",
       %{
         "country" => "Norway",
         "county" => "Innlandet",
         "house_number" => "18",
         "municipality" => "Lillehammer",
         "quarter" => "Langset",
         "road" => "Høstmælingsvegen",
         "town" => "Lillehammer"
       },
       %{
         state: nil,
         house_number: "18",
         road: "Høstmælingsvegen",
         neighbourhood: "Langset",
         city: "Lillehammer",
         county: "Innlandet",
         country: "Norway"
       }},
      {"Tokyo, Shinjuku",
       %{
         "city" => "Shinjuku",
         "country" => "Japan",
         "house_number" => "1",
         "neighbourhood" => "Nishi-Shinjuku 2",
         "quarter" => "Nishi-Shinjuku"
       },
       %{
         state: nil,
         house_number: "1",
         road: nil,
         neighbourhood: "Nishi-Shinjuku 2",
         city: "Shinjuku",
         county: nil,
         country: "Japan"
       }}
    ]

    setup_with_mocks([
      {Tesla.Adapter.Finch, [],
       call: fn %Tesla.Env{} = env, _opts ->
         {:ok, %Tesla.Env{env | status: 200, body: %{"address" => Process.get(:address)}}}
       end}
    ]) do
      :ok
    end

    defp address_fields(address) do
      Process.put(:address, address)
      {:ok, fields} = Geocoder.reverse_lookup(0.0, 0.0)
      fields
    end

    for {field, labels} <- @fields, label <- labels do
      test "#{label} fills #{field} and no other field" do
        fields = address_fields(%{unquote(label) => "value"})

        assert fields[unquote(field)] == "value"
        assert for(name <- @field_names, fields[name] != nil, do: name) == [unquote(field)]
      end
    end

    for {field, labels} <- @fields, [first, second] <- Enum.chunk_every(labels, 2, 1, :discard) do
      test "#{first} goes before #{second} for #{field}" do
        address = %{unquote(first) => "first", unquote(second) => "second"}
        assert %{unquote(field) => "first"} = address_fields(address)
      end
    end

    # Its level varies by country: a municipal district in Ireland, a federal
    # district in Russia.
    test "region fills no field" do
      fields = address_fields(%{"region" => "value"})
      assert for(name <- @field_names, fields[name] != nil, do: name) == []
    end

    for {place, address, fields} <- @recorded do
      test "recorded address: #{place}" do
        address = unquote(Macro.escape(address))
        assert Map.take(address_fields(address), @field_names) == unquote(Macro.escape(fields))
      end
    end
  end
end
