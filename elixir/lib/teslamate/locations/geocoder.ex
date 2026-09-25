defmodule TeslaMate.Locations.Geocoder do
  @version Mix.Project.config()[:version]

  alias TeslaMate.Locations.Address

  defp client do
    Tesla.client(
      [
        {Tesla.Middleware.BaseUrl, "https://nominatim.openstreetmap.org"},
        {Tesla.Middleware.Headers, [{"user-agent", "TeslaMate/#{@version}"}]},
        Tesla.Middleware.JSON,
        {Tesla.Middleware.Logger, debug: true, level: &log_level/1}
      ],
      {Tesla.Adapter.Finch, name: TeslaMate.HTTP, receive_timeout: 30_000}
    )
  end

  defp get(url, opts), do: Tesla.get(client(), url, opts)

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
      |> Enum.map(fn %Address{} = a ->
        "#{String.upcase(String.at(a.osm_type, 0))}#{a.osm_id}"
      end)
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

  # Address fields from Nominatim's address labels
  #
  # A label fills the field whose rank range holds the label's address rank,
  # the way Nominatim assigns ranks to GeocodeJSON fields (GEOCODEJSON_RANKS).
  # The ranks come from settings/address-levels.json, and from ADMIN_LABELS for
  # administrative boundaries; a label with two sources takes the rank of the
  # one used more often in OSM. Within a field the more specific label goes
  # first, and place and boundary labels go before landuse labels, which
  # describe how land is used rather than a locality. territory is undocumented
  # but appears on state-level boundaries (Australian Capital Territory).
  # Sources: https://github.com/osm-search/Nominatim (docs/api/Output.md,
  # settings/address-levels.json, src/nominatim_api/v1/)

  # street: ranks 25-27
  @road_labels ~w(road isolated_dwelling farm city_block mountain_pass square locality)

  # district and locality: ranks 17-24
  @neighbourhood_labels ~w(neighbourhood subdivision quarter suburb hamlet croft borough city_district) ++
                          ~w(residential farmyard industrial commercial allotments retail)

  # city: ranks 13-16
  @city_labels ~w(city town village municipality)

  # county: ranks 10-12
  @county_labels ~w(county district)

  # state: ranks 5-9
  @state_labels ~w(state province territory region)

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
      house_number: get_in(raw, ["address", "house_number"]),
      road: raw["address"] |> get_first(@road_labels),
      neighbourhood: raw["address"] |> get_first(@neighbourhood_labels),
      city: raw["address"] |> get_first(@city_labels),
      county: raw["address"] |> get_first(@county_labels),
      postcode: get_in(raw, ["address", "postcode"]),
      state: raw["address"] |> get_first(@state_labels),
      state_district: get_in(raw, ["address", "state_district"]),
      country: get_in(raw, ["address", "country"]),
      raw: raw
    }

    {:ok, address}
  end

  defp get_first(nil, _aliases), do: nil
  defp get_first(_address, []), do: nil

  defp get_first(address, [key | aliases]) do
    with nil <- Map.get(address, key), do: get_first(address, aliases)
  end

  defp log_level({:ok, %Tesla.Env{} = env}) when env.status >= 400, do: :warning
  defp log_level({:ok, %Tesla.Env{}}), do: :info
  defp log_level({:error, _reason}), do: :error
end
