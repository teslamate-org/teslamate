defmodule TeslaMate.ApiErrorsTest do
  use TeslaMate.DataCase

  alias TeslaMate.Auth.Credentials
  alias TeslaMate.Api

  import Mock

  @valid_credentials %Credentials{email: "teslamate", password: "foo"}

  test "sign_in", %{test: name} do
    login = fn _email, _password -> {:error, %TeslaApi.Error{error: :unauthorized}} end

    with_mock TeslaApi.Auth, login: login do
      :ok = start_real_api(name)
      assert {:error, :unauthorized} = Api.sign_in(@valid_credentials)
    end
  end

  test ":not_signed_in", %{test: name} do
    vehicle_mock =
      {TeslaApi.Vehicle, [],
       [
         list: fn _ -> {:error, %TeslaApi.Error{env: %Tesla.Env{status: 401}}} end,
         get: fn _, _ -> {:error, %TeslaApi.Error{env: %Tesla.Env{status: 401}}} end,
         get_with_state: fn _, _ -> {:error, %TeslaApi.Error{env: %Tesla.Env{status: 401}}} end
       ]}

    with_mocks [auth_mock(), vehicle_mock] do
      :ok = start_real_api(name)

      assert :ok = Api.sign_in(@valid_credentials)
      assert {:error, :not_signed_in} = Api.list_vehicles()

      assert :ok = Api.sign_in(@valid_credentials)
      assert {:error, :not_signed_in} = Api.get_vehicle(0)

      assert :ok = Api.sign_in(@valid_credentials)
      assert {:error, :not_signed_in} = Api.get_vehicle_with_state(0)
    end
  end

  test ":vehicle_not_found", %{test: name} do
    api_error = %TeslaApi.Error{env: %Tesla.Env{status: 404, body: %{"error" => "not_found"}}}

    vehicle_mock =
      {TeslaApi.Vehicle, [],
       [
         get: fn _auth, _id -> {:error, api_error} end,
         get_with_state: fn _auth, _id -> {:error, api_error} end
       ]}

    with_mocks [auth_mock(), vehicle_mock] do
      :ok = start_real_api(name)

      assert :ok = Api.sign_in(@valid_credentials)
      assert {:error, :vehicle_not_found} = Api.get_vehicle(0)
      assert {:error, :vehicle_not_found} = Api.get_vehicle_with_state(0)
    end
  end

  @tag :capture_log
  test "other error witn Env", %{test: name} do
    api_error = %TeslaApi.Error{error: :unkown, env: %Tesla.Env{status: 503, body: ""}}

    vehicle_mock =
      {TeslaApi.Vehicle, [],
       [
         list: fn _auth -> {:error, api_error} end,
         get: fn _auth, _id -> {:error, api_error} end,
         get_with_state: fn _auth, _id -> {:error, api_error} end
       ]}

    with_mocks [auth_mock(), vehicle_mock] do
      :ok = start_real_api(name)

      assert :ok = Api.sign_in(@valid_credentials)
      assert {:error, :unkown} = Api.list_vehicles()
      assert {:error, :unkown} = Api.get_vehicle(0)
      assert {:error, :unkown} = Api.get_vehicle_with_state(0)
    end
  end

  test "other error witnout Env", %{test: name} do
    api_error = %TeslaApi.Error{error: :closed, message: "foo"}

    vehicle_mock =
      {TeslaApi.Vehicle, [],
       [
         list: fn _auth -> {:error, api_error} end,
         get: fn _auth, _id -> {:error, api_error} end,
         get_with_state: fn _auth, _id -> {:error, api_error} end
       ]}

    with_mocks [auth_mock(), vehicle_mock] do
      :ok = start_real_api(name)

      assert :ok = Api.sign_in(@valid_credentials)
      assert {:error, :closed} = Api.list_vehicles()
      assert {:error, :closed} = Api.get_vehicle(0)
      assert {:error, :closed} = Api.get_vehicle_with_state(0)
    end
  end

  defp start_real_api(name) do
    vehicles_name = :"vehicles_#{name}"
    {:ok, _pid} = start_supervised({VehiclesMock, name: vehicles_name, pid: self()})
    {:ok, _} = start_supervised({Api, vehicles: {VehiclesMock, vehicles_name}})
    :ok
  end

  defp auth_mock do
    {TeslaApi.Auth, [],
     [
       login: fn _email, _password ->
         {:ok,
          %TeslaApi.Auth{
            token: "foo",
            refresh_token: "foo",
            type: "foo",
            expires_in: 999_999.0,
            created_at: nil
          }}
       end,
       refresh: fn _auth ->
         {:ok,
          %TeslaApi.Auth{
            token: "foo",
            refresh_token: "foo",
            type: "foo",
            expires_in: 999_999.0,
            created_at: nil
          }}
       end
     ]}
  end
end
