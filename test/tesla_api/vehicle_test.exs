defmodule TeslaApi.VehicleTest do
  use ExUnit.Case, async: false

  import Mock

  alias TeslaApi.{Auth, Vehicle}

  # Regression tests for #4780/#5468: after migrating away from the `use Tesla`
  # macros, the request opts (and with them the access token read by the
  # TokenAuth middleware) were no longer forwarded, so every request against
  # the Owner API was sent without an Authorization header and failed with 401.

  defp adapter_mock(pid, response_body) do
    {Tesla.Adapter.Finch, [],
     call: fn %Tesla.Env{} = env, _opts ->
       send(pid, {:request, env})
       {:ok, %Tesla.Env{env | status: 200, body: response_body}}
     end}
  end

  test "list/1 sends the bearer token of the auth struct" do
    with_mocks [adapter_mock(self(), %{"response" => []})] do
      assert {:ok, []} = Vehicle.list(%Auth{token: "secret-access-token"})

      assert_receive {:request, %Tesla.Env{} = env}
      assert Tesla.get_header(env, "Authorization") == "Bearer secret-access-token"
      assert env.url == "https://owner-api.teslamotors.com/api/1/products"
    end
  end

  test "get_with_state/2 sends the bearer token and the endpoints query" do
    with_mocks [adapter_mock(self(), %{"response" => %{"id" => 42, "state" => "online"}})] do
      assert {:ok, %Vehicle{id: 42, state: "online"}} =
               Vehicle.get_with_state(%Auth{token: "secret-access-token"}, 42)

      assert_receive {:request, %Tesla.Env{} = env}
      assert Tesla.get_header(env, "Authorization") == "Bearer secret-access-token"
      assert env.url == "https://owner-api.teslamotors.com/api/1/vehicles/42/vehicle_data"
      assert [endpoints: "charge_state;" <> _] = env.query
    end
  end
end
