defmodule TeslaMateWeb.CarView do
  use TeslaMateWeb, :view
  alias TeslaMateWeb.CarView

  def render("index.json", %{car: car}) do
    %{data: render_many(car, CarView, "car.json")}
  end

  def render("show.json", %{car: car}) do
    %{data: render_one(car, CarView, "car.json")}
  end

  def render("car.json", %{car: car}) do
    %{
      id: car.id,
      eid: car.eid,
      vid: car.vid,
      model: car.model,
      efficiency: car.efficiency
    }
  end
end
