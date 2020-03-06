defmodule TeslaMate.Locations.Geocoder do
  alias Mojito.{Response, Error}
  alias TeslaMate.Locations.Address

  def reverse_lookup(lat, lon, lang \\ "en") do
    with {:ok, address_raw} <-
           fetch("https://nominatim.openstreetmap.org/reverse", lang,
             format: :jsonv2,
             addressdetails: 1,
             extratags: 1,
             namedetails: 1,
             zoom: 19,
             lat: lat,
             lon: lon
           ) do
      {:ok, into_address(address_raw)}
    end
  end

  def details(addresses, lang) when is_list(addresses) do
    osm_ids =
      addresses
      |> Enum.reject(fn %Address{osm_id: id, osm_type: type} -> is_nil(id) or is_nil(type) end)
      |> Enum.map(fn %Address{osm_id: id, osm_type: type} ->
        "#{type |> String.at(0) |> String.upcase()}#{id}"
      end)
      |> Enum.join(",")

    with {:ok, raw_addresses} <-
           fetch("https://nominatim.openstreetmap.org/lookup", lang,
             osm_ids: osm_ids,
             format: :jsonv2,
             addressdetails: 1,
             extratags: 1,
             namedetails: 1,
             zoom: 19
           ) do
      {:ok, Enum.map(raw_addresses, &into_address/1)}
    end
  end

  defp fetch(url, lang, params) do
    url = assemble_url(url, params)

    case Mojito.get(url, headers(lang), timeout: 15_000) do
      {:ok, %Response{status_code: 200, body: body}} -> {:ok, Jason.decode!(body)}
      {:ok, %Response{body: body}} -> {:error, Jason.decode!(body) |> Map.get("error")}
      {:error, %Error{reason: reason}} -> {:error, reason}
    end
  end

  defp assemble_url(url, params) do
    url
    |> URI.parse()
    |> Map.put(:query, URI.encode_query(params))
    |> URI.to_string()
  end

  defp headers(lang) do
    [
      {"User-Agent", "TeslaMate"},
      {"Content-Type", "application/json"},
      {"Accept-Language", lang},
      {"Accept", "Application/json; Charset=utf-8"}
    ]
  end

  # Address Formatting
  # Source: https://github.com/OpenCageData/address-formatting/blob/master/conf/components.yaml

  @road_aliases [
    "road",
    "footway",
    "street",
    "street_name",
    "residential",
    "path",
    "pedestrian",
    "road_reference",
    "road_reference_intl",
    "square",
    "place"
  ]

  @neighbourhood_aliases [
    "neighbourhood",
    "suburb",
    "city_district",
    "district",
    "quarter",
    "residential",
    "commercial",
    "houses",
    "subdivision"
  ]

  @city_aliases [
    "city",
    "town",
    "municipality",
    "village",
    "hamlet",
    "locality",
    "croft"
  ]

  @county_aliases [
    "county",
    "local_administrative_area",
    "county_code"
  ]

  defp into_address(raw) do
    %{
      display_name: Map.get(raw, "display_name"),
      osm_id: Map.get(raw, "osm_id"),
      osm_type: Map.get(raw, "osm_type"),
      latitude: Map.get(raw, "lat"),
      longitude: Map.get(raw, "lon"),
      name:
        Map.get(raw, "name") || get_in(raw, ["namedetails", "name"]) ||
          get_in(raw, ["namedetails", "alt_name"]),
      house_number: raw["address"] |> get_first(["house_number", "street_number"]),
      road: raw["address"] |> get_first(@road_aliases),
      neighbourhood: raw["address"] |> get_first(@neighbourhood_aliases),
      city: raw["address"] |> get_first(@city_aliases),
      county: raw["address"] |> get_first(@county_aliases),
      postcode: get_in(raw, ["address", "postcode"]),
      state: raw["address"] |> get_first(["state", "province", "state_code"]),
      state_district: get_in(raw, ["address", "state_district"]),
      country: raw["address"] |> get_first(["country", "country_name"]),
      raw: raw
    }
  end

  defp get_first(_address, []), do: nil

  defp get_first(address, [key | aliases]) do
    with nil <- Map.get(address, key), do: get_first(address, aliases)
  end
end
