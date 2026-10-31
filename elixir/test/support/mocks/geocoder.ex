defmodule GeocoderMock do
  alias TeslaMate.Locations.Address

  def reverse_lookup(lat, lon, lang) do
    refute_checked_out!()
    lookup(lat, lon, lang)
  end

  defp lookup(%Decimal{} = lat, %Decimal{} = lon, lang) do
    lookup(Decimal.to_float(lat), Decimal.to_float(lon), lang)
  end

  defp lookup(99.9, 99.9, _lang) do
    {:error, :induced_error}
  end

  defp lookup(-99.9, -99.9, _lang) do
    {:ok,
     %{
       display_name: "Unknown",
       osm_type: "unknown",
       osm_id: 0,
       latitude: 0.0,
       longitude: 0.0,
       raw: %{"error" => "Unable to geocode"}
     }}
  end

  defp lookup(lat, lng, _lang)
       when lat in [52.51599, 52.515, 52.514521] and lng in [13.35199, 13.351, 13.350144] do
    {:ok,
     %{
       city: nil,
       country: "Germany",
       county: nil,
       display_name: "1, Großer Stern, Tiergarten, Mitte, Berlin, 10787, Germany",
       house_number: "1",
       latitude: "52.5145069",
       longitude: "13.3501101",
       name: nil,
       neighbourhood: "Tiergarten",
       osm_id: 89_721_012,
       osm_type: "way",
       postcode: "10787",
       raw: %{
         "city_district" => "Mitte",
         "country" => "Germany",
         "country_code" => "de",
         "house_number" => "1",
         "postcode" => "10787",
         "road" => "Großer Stern",
         "state" => "Berlin",
         "suburb" => "Tiergarten"
       },
       road: "Großer Stern",
       state: "Berlin",
       state_district: nil
     }}
  end

  defp lookup(52.394246, 13.542552, _lang) do
    {:ok,
     %{
       city: nil,
       country: "Germany",
       county: nil,
       display_name:
         "Tesla Store & Service Center Berlin, 24-26, Alexander-Meißner-Straße, Altglienicke, Treptow-Köpenick, Berlin, 12526, Germany",
       house_number: "24-26",
       latitude: "52.3941049",
       longitude: "13.5425707",
       name: "Tesla Store & Service Center Berlin",
       neighbourhood: "Altglienicke",
       osm_id: 64_445_009,
       osm_type: "way",
       postcode: "12526",
       raw: %{
         "car" => "Tesla Store & Service Center Berlin",
         "city_district" => "Treptow-Köpenick",
         "country" => "Germany",
         "country_code" => "de",
         "house_number" => "24-26",
         "postcode" => "12526",
         "road" => "Alexander-Meißner-Straße",
         "state" => "Berlin",
         "suburb" => "Altglienicke"
       },
       road: "Alexander-Meißner-Straße",
       state: "Berlin",
       state_district: nil
     }}
  end

  defp lookup(-25.066188, -130.100502, _lang) do
    {:ok,
     %{
       city: "Adamstown",
       country: "Pitcairn Islands",
       county: nil,
       display_name: "Adamstown, Pitcairn Islands",
       house_number: nil,
       latitude: "-25.0661235097694",
       longitude: "-130.100512324384",
       name: nil,
       neighbourhood: nil,
       osm_id: 246_879_822,
       osm_type: "way",
       postcode: nil,
       raw: %{
         "country" => "Pitcairn Islands",
         "country_code" => "pn",
         "town" => "Adamstown"
       },
       road: nil,
       state: nil,
       state_district: nil
     }}
  end

  defp lookup(lat, lon, _lang) when is_number(lat) and is_number(lon) do
    {:ok,
     %{
       city: "Bielefeld",
       country: "Deutschland",
       county: nil,
       display_name:
         "Von-der-Recke-Straße, Mitte, Bielefeld, Regierungsbezirk Detmold, Nordrhein-Westfalen, 33602, Deutschland",
       house_number: nil,
       latitude: "52.0196010141104",
       longitude: "8.52631835353143",
       name: "Von-der-Recke-Straße",
       neighbourhood: "Mitte",
       osm_id: 103_619_766,
       osm_type: "way",
       postcode: "33602",
       raw: %{
         "city" => "Bielefeld",
         "country" => "Deutschland",
         "country_code" => "de",
         "postcode" => "33602",
         "road" => "Von-der-Recke-Straße",
         "state" => "Nordrhein-Westfalen",
         "state_district" => "Regierungsbezirk Detmold",
         "suburb" => "Mitte"
       },
       road: "Von-der-Recke-Straße",
       state: "Nordrhein-Westfalen"
     }}
  end

  # Tests never sleep: the calling process is told about each pause instead.
  def pause(ms) do
    send(self(), {:pause, ms, checked_out?: TeslaMate.Repo.checked_out?()})
    :ok
  end

  # Like Nominatim, it does not answer the lookup of some addresses: those
  # are reverse geocoded instead.
  def details(addresses, lang) do
    refute_checked_out!()

    {:ok,
     addresses
     |> Enum.reject(&match?(%Address{display_name: "not_in_lookup"}, &1))
     |> Enum.map(fn
       %Address{display_name: "error"} ->
         throw({:error, :boom})

       %Address{display_name: "crash"} ->
         raise "induced crash"

       %Address{} = address ->
         address
         |> Map.from_struct()
         |> Map.update(:name, "", fn val -> "#{val}_#{lang}" end)
         |> Map.update(:state, "", fn val -> "#{val}_#{lang}" end)
         |> Map.update(:country, "", fn _ -> "#{lang}" end)
     end)}
  catch
    {:error, :boom} ->
      {:error, :boom}
  end

  # Requests to Nominatim take a while: a checked out DB connection would be
  # held that long.
  defp refute_checked_out! do
    if TeslaMate.Repo.checked_out?(), do: raise("Geocoding with a checked out DB connection")
  end
end
