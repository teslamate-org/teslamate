defmodule TeslaMate.Vehicles.Vehicle.Convert do
  def mph_to_kmh(nil), do: nil
  def mph_to_kmh(mph), do: round(mph * 1.60934)

  def miles_to_km(nil, _precision), do: nil
  def miles_to_km(miles, precision), do: Float.round(miles / 0.62137, precision)
end
