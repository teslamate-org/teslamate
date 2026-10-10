defmodule TeslaMateWeb.VehicleReload do
  @moduledoc """
  User-facing wording for the outcome of `TeslaMate.Vehicles.discover/0`,
  shared by the car overview and the settings page.
  """
  use Gettext, backend: TeslaMateWeb.Gettext

  alias TeslaMate.Log.Car
  alias TeslaMate.Vehicles

  @doc "Explains a discovery result; `nil` for a result that needs no explanation."
  @spec hint(Vehicles.discovery() | nil) :: String.t() | nil
  def hint(nil), do: nil

  def hint({:ok, []}), do: gettext("No new vehicle was found in your Tesla account.")

  def hint({:ok, [_ | _] = cars}) do
    names = Enum.map_join(cars, ", ", fn %Car{name: name, vin: vin} -> name || vin end)
    gettext("Started logging for: %{names}", names: names)
  end

  def hint({:error, :no_vehicles}) do
    gettext(
      "Your Tesla account does not contain a vehicle yet. Once the vehicle shows up in the Tesla app, reload the vehicle list."
    )
  end

  def hint({:error, :too_many_request}) do
    gettext(
      "The Tesla API rate limit was exceeded while fetching the vehicles. Please wait a few minutes before reloading."
    )
  end

  def hint({:error, %Ecto.Changeset{}}) do
    gettext("A vehicle could not be saved to the database. Please check the logs.")
  end

  def hint({:error, reason}) do
    gettext("Fetching the vehicles from the Tesla API failed: %{reason}", reason: inspect(reason))
  end

  @doc "Wording for a discovery whose process crashed."
  def crashed, do: gettext("Reloading the vehicles failed. Please check the logs.")
end
