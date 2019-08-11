defmodule TeslaMate.Locations.Geocoder do
  alias HTTPoison.{Response, Error}

  @lang Application.get_env(:gettext, :default_locale, "en")

  def reverse_lookup(lat, lon) do
    with {:ok, address_raw} <-
           fetch("https://nominatim.openstreetmap.org/reverse",
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

  defp fetch(url, params) do
    case HTTPoison.get(url, headers(), params: params) do
      {:ok, %Response{status_code: 200, body: body}} -> {:ok, Jason.decode!(body)}
      {:ok, %Response{body: body}} -> {:error, Jason.decode!(body) |> Map.get("error")}
      {:error, %Error{reason: reason}} -> {:error, reason}
    end
  end

  defp headers do
    [
      {"User-Agent", "TeslaMate"},
      {"Content-Type", "application/json"},
      {"Accept-Language", @lang},
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
    "road_reference_intl"
  ]

  @neighbourhood_aliases [
    "neighbourhood",
    "suburb",
    "city_district",
    "district",
    "quarter",
    "houses",
    "subdivision"
  ]

  @city_aliases [
    "village",
    "hamlet",
    "locality",
    "croft",
    "city",
    "town",
    "municipality"
  ]

  @county_aliases [
    "county",
    "local_administrative_area",
    "county_code"
  ]

  defp into_address(raw) do
    %{
      display_name: Map.get(raw, "display_name"),
      place_id: Map.get(raw, "place_id"),
      latitude: Map.get(raw, "lat"),
      longitude: Map.get(raw, "lon"),
      name: Map.get(raw, "name"),
      house_number: raw["address"] |> get_first(["house_number", "street_number"]),
      road: raw["address"] |> get_first(@road_aliases),
      neighbourhood: raw["address"] |> get_first(@neighbourhood_aliases),
      city: raw["address"] |> get_first(@city_aliases),
      county: raw["address"] |> get_first(@county_aliases),
      postcode: get_in(raw, ["address", "postcode"]),
      state: raw["address"] |> get_first(["state", "province", "state_code"]),
      state_district: get_in(raw, ["address", "state_district"]),
      country: raw["address"] |> get_first(["country", "country_name"]),
      raw: raw["address"]
    }
  end

  defp get_first(_address, []), do: nil

  defp get_first(address, [key | aliases]) do
    with nil <- Map.get(address, key), do: get_first(address, aliases)
  end
end
