defmodule TeslaMate.Locations.Geocoder do
  use Tesla, only: [:get]

  @version Mix.Project.config()[:version]

  adapter Tesla.Adapter.Finch, name: TeslaMate.HTTP, receive_timeout: 30_000

  plug Tesla.Middleware.BaseUrl, "https://nominatim.openstreetmap.org"
  plug Tesla.Middleware.Headers, [{"user-agent", "TeslaMate/#{@version}"}]
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Logger, debug: true, log_level: &log_level/1

  alias TeslaMate.Locations.Address

  def reverse_lookup(lat, lon, lang \\ "en") do
    opts = [
      format: :jsonv2,
      addressdetails: 1,
      extratags: 1,
      namedetails: 1,
      zoom: 19,
      lat: lat,
      lon: lon
    ]

    with {:ok, address_raw} <- query("/reverse", lang, opts),
         {:ok, address} <- into_address(address_raw) do
      {:ok, address}
    end
  end

  def details(addresses, lang) when is_list(addresses) do
    osm_ids =
      addresses
      |> Enum.reject(fn %Address{} = a -> a.osm_id == nil or a.osm_type in [nil, "unknown"] end)
      |> Enum.map(fn %Address{} = a -> "#{String.upcase(String.at(a.osm_type, 0))}#{a.osm_id}" end)
      |> Enum.join(",")

    params = [
      osm_ids: osm_ids,
      format: :jsonv2,
      addressdetails: 1,
      extratags: 1,
      namedetails: 1,
      zoom: 19
    ]

    with {:ok, raw_addresses} <- query("/lookup", lang, params) do
      addresses =
        Enum.map(raw_addresses, fn attrs ->
          case into_address(attrs) do
            {:ok, address} -> address
            {:error, reason} -> throw({:invalid_address, reason})
          end
        end)

      {:ok, addresses}
    end
  catch
    {:invalid_address, reason} ->
      {:error, reason}
  end

  defp query(url, lang, params) do
    case get(url, query: params, headers: [{"Accept-Language", lang}]) do
      {:ok, %Tesla.Env{status: 200, body: body}} -> {:ok, body}
      {:ok, %Tesla.Env{body: %{"error" => reason}}} -> {:error, reason}
      {:ok, %Tesla.Env{} = env} -> {:error, reason: "Unexpected response", env: env}
      {:error, reason} -> {:error, reason}
    end
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

  defp into_address(%{"error" => "Unable to geocode"} = raw) do
    unknown_address = %{
      display_name: "Unknown",
      osm_type: "unknown",
      osm_id: 0,
      latitude: 0.0,
      longitude: 0.0,
      raw: raw
    }

    {:ok, unknown_address}
  end

  defp into_address(%{"error" => reason}) do
    {:error, {:geocoding_failed, reason}}
  end

  defp into_address(raw) do
    address = %{
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

    {:ok, address}
  end

  defp get_first(nil, _aliases), do: nil
  defp get_first(_address, []), do: nil

  defp get_first(address, [key | aliases]) do
    with nil <- Map.get(address, key), do: get_first(address, aliases)
  end

  defp log_level(%Tesla.Env{} = env) when env.status >= 400, do: :warn
  defp log_level(%Tesla.Env{}), do: :info
end
