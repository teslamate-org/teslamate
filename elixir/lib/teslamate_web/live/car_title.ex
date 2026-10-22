defmodule TeslaMateWeb.CarTitle do
  @moduledoc """
  User-facing title of a car, shared by every page that names one: cars
  without a name are titled by their full VIN.
  """
  use Gettext, backend: TeslaMateWeb.Gettext

  alias TeslaMate.Log.Car

  @doc """
  Returns the title and the VIN label shown next to it. A car without a name
  shows its full VIN as title and label; a named car is labeled by the last six
  characters of its VIN.
  """
  @spec format(String.t() | nil, String.t()) :: {String.t(), String.t()}
  def format(name, vin) when name in [nil, ""] do
    label = gettext("VIN %{vin}", vin: vin)
    {label, label}
  end

  def format(name, vin) do
    {name, gettext("VIN %{vin}", vin: String.slice(vin, -6, 6))}
  end

  @doc "Returns only the title of `format/2`."
  @spec title(Car.t()) :: String.t()
  def title(%Car{name: name, vin: vin}) do
    {title, _vin_label} = format(name, vin)
    title
  end
end
