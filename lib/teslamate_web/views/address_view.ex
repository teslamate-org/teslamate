defmodule TeslaMateWeb.AddressView do
  use TeslaMateWeb, :view
  alias TeslaMateWeb.AddressView

  def render("index.json", %{addresses: addresses}) do
    %{data: render_many(addresses, AddressView, "address.json")}
  end

  def render("show.json", %{address: address}) do
    %{data: render_one(address, AddressView, "address.json")}
  end

  def render("address.json", %{address: address}) do
    %{
      id: address.id,
      display_name: address.display_name,
      place_id: address.place_id,
      latitude: address.latitude,
      longitude: address.longitude,
      name: address.name,
      house_number: address.house_number,
      road: address.road,
      neighbourhood: address.neighbourhood,
      city: address.city,
      county: address.county,
      postcode: address.postcode,
      state: address.state,
      state_district: address.state_district,
      country: address.country,
      raw: address.raw
    }
  end
end
