defmodule GeocoderMock do
  def reverse_lookup(_lat, _lon) do
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
       place_id: 103_619_766,
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
end
