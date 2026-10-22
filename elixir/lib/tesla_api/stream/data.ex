defmodule TeslaApi.Stream.Data do
  defstruct ~w(time speed odometer soc elevation est_heading est_lat est_lng power shift_state range
               est_range heading)a

  def into!(raw) do
    data =
      raw
      |> Map.update(:time, nil, &to_dt/1)
      |> Map.update(:elevation, nil, &to_i/1)
      |> Map.update(:est_heading, nil, &to_i/1)
      |> Map.update(:est_lat, nil, &to_f/1)
      |> Map.update(:est_lng, nil, &to_f/1)
      |> Map.update(:est_range, nil, &to_i/1)
      |> Map.update(:heading, nil, &to_i/1)
      |> Map.update(:odometer, nil, &to_f/1)
      |> Map.update(:power, nil, &to_i/1)
      |> Map.update(:range, nil, &to_i/1)
      |> Map.update(:shift_state, nil, &to_s/1)
      |> Map.update(:soc, nil, &to_i/1)
      |> Map.update(:speed, nil, &to_i/1)

    struct!(__MODULE__, data)
  end

  defp to_s(""), do: nil
  defp to_s(str), do: str

  defp to_f(""), do: nil
  defp to_f(str), do: parse(Float, str)

  defp to_i(""), do: nil
  defp to_i(str), do: parse(Integer, str)

  defp parse(mod, str) when mod in [Integer, Float] do
    case apply(mod, :parse, [str]) do
      {f, ""} -> f
      _ -> nil
    end
  end

  defp to_dt(str) when is_binary(str) do
    str
    |> String.to_integer()
    |> DateTime.from_unix!(:millisecond)
  end
end
