defmodule TeslaApi.ChargingHistoryTest do
  use ExUnit.Case, async: false

  import Mock

  alias TeslaApi.{Auth, ChargingHistory, Error}
  alias ChargingHistory.{Result, Session}

  defp adapter_mock(pid, response_fun) do
    {Tesla.Adapter.Finch, [],
     call: fn %Tesla.Env{} = env, _opts ->
       send(pid, {:request, env})
       {status, headers, body} = response_fun.(env)
       {:ok, %Tesla.Env{env | status: status, headers: headers, body: body}}
     end}
  end

  defp history_response(sessions, opts \\ []) do
    %{
      "data" => %{
        "me" => %{
          "charging" => %{
            "historyV2" => %{
              "data" => sessions,
              "hasMoreData" => Keyword.get(opts, :has_more, false),
              "pageNumber" => Keyword.get(opts, :page, 1),
              "totalResults" => Keyword.get(opts, :total, length(sessions))
            }
          }
        }
      }
    }
  end

  test "sends the owner token and normalizes energy and all explicit fees" do
    response =
      history_response([
        %{
          "chargeSessionId" => "session-1",
          "siteLocationName" => "Paris",
          "chargeStartDateTime" => "2026-08-01T10:00:00+02:00",
          "chargeStopDateTime" => "2026-08-01T10:30:00+02:00",
          "fees" => [
            %{
              "feeType" => "CHARGING",
              "usageBase" => 42.5,
              "totalDue" => 12.3,
              "currencyCode" => "EUR"
            },
            %{"feeType" => "PARKING", "totalDue" => 1.2, "currencyCode" => "EUR"}
          ]
        }
      ])

    with_mocks [adapter_mock(self(), fn _env -> {200, [], response} end)] do
      assert {:ok, %Result{sessions: [%Session{} = session]}} =
               ChargingHistory.get(%Auth{token: "secret-access-token"}, "VIN", page_limit: 1)

      assert session.id == "session-1"
      assert session.location == "Paris"
      assert session.currency == "EUR"
      assert Decimal.equal?(session.energy, Decimal.new("42.5"))
      assert Decimal.equal?(session.cost, Decimal.new("13.5"))
      assert session.start_date == ~U[2026-08-01 08:00:00Z]

      assert_receive {:request, %Tesla.Env{} = env}
      assert Tesla.get_header(env, "Authorization") == "Bearer secret-access-token"
      assert env.url == "https://akamai-apigateway-charging-ownership.tesla.com/graphql"

      assert env.query == [
               deviceLanguage: "en",
               deviceCountry: "US",
               ttpLocale: "en_US",
               vin: "VIN",
               operationName: "getChargingHistoryV2"
             ]

      assert Tesla.get_header(env, "user-agent") == "okhttp/4.11.0"
      assert Tesla.get_header(env, "accept-language") == "en"
      assert Tesla.get_header(env, "charset") == "utf-8"
      assert Tesla.get_header(env, "cache-control") == "no-cache"
    end
  end

  test "paginates and keeps an explicit zero distinct from missing fees" do
    response_fun = fn env ->
      page = env.body |> Jason.decode!() |> get_in(["variables", "pageNumber"])

      body =
        case page do
          1 ->
            history_response(
              [
                %{
                  "sessionId" => 1,
                  "chargeStartDateTime" => "2026-08-02T10:00:00Z",
                  "fees" => [%{"feeType" => "CHARGING", "totalDue" => 0}]
                }
              ],
              has_more: true,
              page: 1,
              total: 2
            )

          2 ->
            history_response(
              [
                %{
                  "sessionId" => 2,
                  "chargeStartDateTime" => "invalid",
                  "fees" => []
                }
              ],
              page: 2,
              total: 2
            )
        end

      {200, [], body}
    end

    with_mocks [adapter_mock(self(), response_fun)] do
      assert {:ok, %Result{sessions: [free, pending], total_results: 2}} =
               ChargingHistory.get(%Auth{token: "token"}, "VIN")

      assert Decimal.equal?(free.cost, Decimal.new(0))
      assert pending.cost == nil
      assert pending.start_date == nil
      assert_receive {:request, _}
      assert_receive {:request, _}
    end
  end

  test "returns structured authentication, rate-limit and GraphQL errors" do
    auth = %Auth{token: "token"}

    with_mocks [adapter_mock(self(), fn _ -> {401, [], %{}} end)] do
      assert {:error, %Error{reason: :unauthorized}} = ChargingHistory.get(auth, "VIN")
    end

    with_mocks [adapter_mock(self(), fn _ -> {429, [{"retry-after", "42"}], %{}} end)] do
      assert {:error, %Error{reason: :too_many_request, message: 42}} =
               ChargingHistory.get(auth, "VIN")
    end

    with_mocks [
      adapter_mock(self(), fn _ -> {200, [], %{"errors" => [%{"message" => "no"}]}} end)
    ] do
      assert {:error, %Error{reason: :charging_history}} = ChargingHistory.get(auth, "VIN")
    end
  end
end
