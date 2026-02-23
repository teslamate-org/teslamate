defmodule TeslaMateWeb.Api.ChargeController do
  use TeslaMateWeb, :controller

  alias TeslaMate.Log
  alias TeslaMateWeb.Api.Views.ChargeJSON

  action_fallback TeslaMateWeb.Api.FallbackController

  def index(conn, %{"car_id" => car_id} = params) do
    opts =
      [
        page: parse_int(params["page"], 1),
        per_page: parse_int(params["per_page"], 20)
      ]
      |> maybe_put_date(:since, params["since"])
      |> maybe_put_date(:until, params["until"])

    result = Log.list_charging_processes(String.to_integer(car_id), opts)

    json(conn, %{
      data: Enum.map(result.entries, &ChargeJSON.charging_process/1),
      page: result.page,
      per_page: result.per_page,
      total: result.total
    })
  end

  def show(conn, %{"id" => id}) do
    case Log.get_charging_process_with_charges(id) do
      nil ->
        {:error, :not_found}

      {cp, charges} ->
        json(conn, %{
          data: %{
            charging_process: ChargeJSON.charging_process_detail(cp),
            charges: Enum.map(charges, &ChargeJSON.charge/1)
          }
        })
    end
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
