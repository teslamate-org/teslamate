defmodule TeslaMate.Convert do
  def mph_to_kmh(nil), do: nil
  def mph_to_kmh(mph), do: round(mph * 1.60934)

  def miles_to_km(nil, _precision), do: nil
  def miles_to_km(miles, precision), do: Float.round(miles / 0.62137, precision)

  def km_to_miles(nil, _precision), do: nil
  def km_to_miles(km, precision), do: Float.round(km * 0.62137, precision)

  def m_to_ft(nil), do: nil
  def m_to_ft(m), do: m * 3.28084

  def ft_to_m(nil), do: nil
  def ft_to_m(ft), do: ft / 3.28084

  @minute 60
  @hour @minute * 60
  @day @hour * 24
  @week @day * 7
  @divisor [@week, @day, @hour, @minute, 1]

  def sec_to_str(sec) when is_number(sec) do
    {_, [s, m, h, d, w]} =
      Enum.reduce(@divisor, {sec, []}, fn divisor, {n, acc} ->
        {rem(n, divisor), [div(n, divisor) | acc]}
      end)

    ["#{w} wk", "#{d} d", "#{h} h", "#{m} min", "#{s} s"]
    |> Enum.reject(&String.starts_with?(&1, "0"))
    |> Enum.take(2)
  end
end
