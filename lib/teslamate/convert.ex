defmodule TeslaMate.Convert do
  @km_factor 0.62137119223733
  @km_factor_d Decimal.from_float(@km_factor)
  @ft_factor 3.28084
  @ft_factor_d Decimal.from_float(@ft_factor)

  alias Decimal, as: D

  def mph_to_kmh(nil), do: nil
  def mph_to_kmh(mph = %D{}), do: mph |> D.div(@km_factor_d) |> D.round()
  def mph_to_kmh(mph), do: round(mph / @km_factor)

  def miles_to_km(nil, _precision), do: nil
  def miles_to_km(mi = %D{}, p), do: mi |> D.div(@km_factor_d) |> D.round(p)
  def miles_to_km(mi, 0), do: round(mi / @km_factor)
  def miles_to_km(mi, precision), do: Float.round(mi / @km_factor, precision)

  def km_to_miles(nil, _precision), do: nil
  def km_to_miles(km = %D{}, p), do: km |> D.mult(@km_factor_d) |> D.round(p)
  def km_to_miles(km, 0), do: round(km * @km_factor)
  def km_to_miles(km, precision), do: Float.round(km * @km_factor, precision)

  def m_to_ft(nil), do: nil
  def m_to_ft(m = %D{}), do: D.mult(m, @ft_factor_d)
  def m_to_ft(m), do: m * @ft_factor

  def ft_to_m(nil), do: nil
  def ft_to_m(ft = %D{}), do: D.div(ft, @ft_factor_d)
  def ft_to_m(ft), do: ft / @ft_factor

  def celsius_to_fahrenheit(nil, _precision), do: nil
  def celsius_to_fahrenheit(c = %D{}, p), do: D.mult(c, 9) |> D.div(5) |> D.add(32) |> D.round(p)
  def celsius_to_fahrenheit(c, 0), do: round(c * 9 / 5 + 32)
  def celsius_to_fahrenheit(c, precision), do: Float.round(c * 9 / 5 + 32, precision)

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
