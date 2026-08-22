defmodule TeslaApi.ChargingHistory do
  alias TeslaApi.{Auth, Error}

  defmodule Session do
    defstruct [
      :id,
      :start_date,
      :end_date,
      :location,
      :energy,
      :cost,
      :currency
    ]
  end

  defmodule Result do
    defstruct sessions: [], total_results: 0
  end

  @endpoint "https://akamai-apigateway-charging-ownership.tesla.com"
  @mobile_user_agent "com.teslamotors.tesla/4.41.0/723d1365/android/14"
  @device_language "en"
  @device_country "US"
  @ttp_locale "en_US"
  @sensitive_headers ~w(Authorization authorization)

  @query """
  query getChargingHistoryV2($pageNumber: Int!, $sortBy: String, $sortOrder: SortByEnum, $latestSession: Boolean) {
    me {
      charging {
        historyV2(
          pageNumber: $pageNumber
          sortBy: $sortBy
          sortOrder: $sortOrder
          latestSession: $latestSession
        ) {
          data {
            chargeSessionId
            sessionId
            siteLocationName
            chargeStartDateTime
            chargeStopDateTime
            chargingPackage {
              energyApplied
            }
            fees {
              feeType
              usageBase
              totalDue
              currencyCode
            }
          }
          hasMoreData
          pageNumber
          totalResults
        }
      }
    }
  }
  """

  def get(%Auth{} = auth, vin, opts \\ []) when is_binary(vin) do
    page_limit = Keyword.get(opts, :page_limit, :all)
    fetch_pages(auth, vin, 1, page_limit, [], 0)
  end

  defp fetch_pages(_auth, _vin, page, page_limit, sessions, total)
       when is_integer(page_limit) and page > page_limit do
    {:ok, %Result{sessions: Enum.reverse(sessions), total_results: total}}
  end

  defp fetch_pages(%Auth{} = auth, vin, page, page_limit, sessions, total) when page <= 100 do
    with {:ok, history} <- fetch_page(auth, vin, page) do
      batch = Enum.map(history["data"] || [], &session/1)
      sessions = Enum.reverse(batch, sessions)
      total = history["totalResults"] || total

      if history["hasMoreData"] and batch != [] do
        fetch_pages(auth, vin, page + 1, page_limit, sessions, total)
      else
        {:ok, %Result{sessions: Enum.reverse(sessions), total_results: total}}
      end
    end
  end

  defp fetch_pages(_auth, _vin, _page, _page_limit, _sessions, _total) do
    {:error, %Error{reason: :charging_history, message: "more than 100 pages returned"}}
  end

  defp fetch_page(%Auth{} = auth, vin, page) do
    body = %{
      "query" => @query,
      "variables" => %{
        "sortBy" => "start_datetime",
        "sortOrder" => "DESC",
        "pageNumber" => page,
        "latestSession" => false
      },
      "operationName" => "getChargingHistoryV2"
    }

    Tesla.post(client(), "/graphql", body,
      query: [
        deviceLanguage: @device_language,
        deviceCountry: @device_country,
        ttpLocale: @ttp_locale,
        vin: vin,
        operationName: "getChargingHistoryV2"
      ],
      opts: [access_token: auth.token]
    )
    |> handle_response()
  end

  defp client do
    request_id = request_id()

    Tesla.client(
      [
        {Tesla.Middleware.BaseUrl, @endpoint},
        {Tesla.Middleware.Headers,
         [
           {"accept", "*/*"},
           {"content-type", "application/json"},
           {"user-agent", "okhttp/4.11.0"},
           {"x-tesla-user-agent", @mobile_user_agent},
           {"x-request-id", request_id},
           {"x-txid", request_id},
           {"accept-language", @device_language},
           {"charset", "utf-8"},
           {"cache-control", "no-cache"}
         ]},
        Tesla.Middleware.JSON,
        TeslaApi.Middleware.TokenAuth,
        {Tesla.Middleware.Logger,
         debug: true,
         filter_headers: @sensitive_headers,
         format: &TeslaApi.format_log/3,
         level: &log_level/1}
      ],
      {Tesla.Adapter.Finch, name: TeslaMate.HTTP, receive_timeout: 35_000}
    )
  end

  defp handle_response(
         {:ok,
          %Tesla.Env{
            status: status,
            body: %{"data" => %{"me" => %{"charging" => %{"historyV2" => history}}}}
          }}
       )
       when status in 200..299 and is_map(history),
       do: {:ok, history}

  defp handle_response({:ok, %Tesla.Env{status: status, body: %{"errors" => errors}} = env})
       when status in 200..299 do
    {:error, %Error{reason: :charging_history, message: inspect(errors), env: env}}
  end

  defp handle_response({:ok, %Tesla.Env{status: 401} = env}),
    do: {:error, %Error{reason: :unauthorized, env: env}}

  defp handle_response({:ok, %Tesla.Env{status: 429, headers: headers}}) do
    retry_after =
      case Enum.find(headers, fn {key, _value} -> String.downcase(key) == "retry-after" end) do
        nil ->
          300

        {_key, value} ->
          case Integer.parse(value) do
            {seconds, ""} -> seconds
            _error -> 300
          end
      end

    {:error, %Error{reason: :too_many_request, message: retry_after}}
  end

  defp handle_response(response), do: Error.into(response, :charging_history)

  defp session(data) do
    fees = data["fees"] || []
    charging_fee = Enum.find(fees, &(Map.get(&1, "feeType") == "CHARGING")) || List.first(fees)

    %Session{
      id: data["chargeSessionId"] || data["sessionId"],
      start_date: parse_datetime(data["chargeStartDateTime"]),
      end_date: parse_datetime(data["chargeStopDateTime"]),
      location: data["siteLocationName"],
      energy:
        decimal(get_in(data, ["chargingPackage", "energyApplied"])) ||
          decimal(charging_fee && charging_fee["usageBase"]),
      cost: total_cost(fees),
      currency:
        (charging_fee && charging_fee["currencyCode"]) ||
          get_in(List.first(fees) || %{}, ["currencyCode"])
    }
  end

  defp total_cost(fees) do
    costs = fees |> Enum.map(&decimal(&1["totalDue"])) |> Enum.reject(&is_nil/1)
    if costs == [], do: nil, else: Enum.reduce(costs, Decimal.new(0), &Decimal.add/2)
  end

  defp decimal(nil), do: nil
  defp decimal(value) when is_integer(value), do: Decimal.new(value)
  defp decimal(value) when is_float(value), do: Decimal.from_float(value)

  defp decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> decimal
      _error -> nil
    end
  end

  defp decimal(_value), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp request_id do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)

    Enum.join(
      [
        Integer.to_string(a, 16) |> String.pad_leading(8, "0"),
        Integer.to_string(b, 16) |> String.pad_leading(4, "0"),
        Integer.to_string(c, 16) |> String.pad_leading(4, "0"),
        Integer.to_string(d, 16) |> String.pad_leading(4, "0"),
        Integer.to_string(e, 16) |> String.pad_leading(12, "0")
      ],
      "-"
    )
  end

  defp log_level({:ok, %Tesla.Env{} = env}) when env.status >= 500, do: :warning
  defp log_level({:ok, %Tesla.Env{} = env}) when env.status >= 400, do: :info
  defp log_level({:ok, %Tesla.Env{}}), do: :debug
  defp log_level({:error, _reason}), do: :error
end
