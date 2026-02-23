defmodule TeslaMateWeb.Api.PositionController do
  use TeslaMateWeb, :controller

  alias TeslaMate.Log
  alias TeslaMateWeb.Api.Views.PositionJSON

  def index(conn, %{"car_id" => car_id} = params) do
    opts =
      [
        page: parse_int(params["page"], 1),
        per_page: parse_int(params["per_page"], 100)
      ]
      |> maybe_put_date(:since, params["since"])
      |> maybe_put_date(:until, params["until"])

    positions = Log.list_positions(String.to_integer(car_id), opts)
    json(conn, %{data: Enum.map(positions, &PositionJSON.position/1)})
  end

  defp parse_int(nil, default), do: default
  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> default
    end
  end

  defp maybe_put_date(opts, _key, nil), do: opts
  defp maybe_put_date(opts, key, val) do
    case DateTime.from_iso8601(val) do
      {:ok, dt, _} -> Keyword.put(opts, key, dt)
      _ -> opts
    end
  end
end
