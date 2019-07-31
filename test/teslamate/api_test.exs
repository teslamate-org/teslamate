defmodule TeslaMate.ApiTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Api
  alias TeslaMate.Auth.{Tokens, Credentials}

  def start_api(name, opts \\ []) do
    auth_name = :"auth_#{name}"
    vehicles_name = :"vehicles_#{name}"
    tesla_api_auth_name = :"tesla_api_auth_#{name}"
    tesla_api_vehicle_name = :"tesla_api_vehicle_#{name}"

    tokens = Keyword.get(opts, :tokens)
    credentials = Keyword.get(opts, :credentials)

    {:ok, _pid} =
      start_supervised(
        {AuthMock, name: auth_name, tokens: tokens, credentials: credentials, pid: self()}
      )

    {:ok, _pid} = start_supervised({VehiclesMock, name: vehicles_name, pid: self()})
    {:ok, _pid} = start_supervised({TeslaApi.AuthMock, name: tesla_api_auth_name, pid: self()})

    {:ok, _pid} =
      start_supervised({TeslaApi.VehicleMock, name: tesla_api_vehicle_name, pid: self()})

    with {:ok, _} <-
           start_supervised(
             {Api,
              [
                name: name,
                auth: {AuthMock, auth_name},
                vehicles: {VehiclesMock, vehicles_name},
                tesla_api_auth: {TeslaApi.AuthMock, tesla_api_auth_name},
                tesla_api_vehicle: {TeslaApi.VehicleMock, tesla_api_vehicle_name}
              ]}
           ) do
      :ok
    end
  end

  @valid_tokens %Tokens{access: "$access", refresh: "$refresh"}
  @invalid_tokens %Tokens{access: nil, refresh: nil}
  @valid_credentials %Credentials{email: "teslamate", password: "foo"}
  @invalid_credentials %Credentials{email: nil, password: nil}

  describe "sign in" do
    test "starts without tokens and credentials", %{test: name} do
      :ok = start_api(name, tokens: nil, credentials: nil)

      assert false == Api.signed_in?(name)
      assert {:error, :not_signed_in} = Api.list_vehicles(name)
      assert {:error, :not_signed_in} = Api.get_vehicle(name, 0)
      assert {:error, :not_signed_in} = Api.get_vehicle_with_state(name, 0)

      refute_receive _
    end

    test "starts if tokens are valid", %{test: name} do
      :ok = start_api(name, tokens: @valid_tokens, credentials: nil)

      assert_receive {TeslaApi.AuthMock,
                      {:refresh, %TeslaApi.Auth{refresh_token: "$refresh", token: "$access"}}}

      assert_receive {AuthMock, {:save, %TeslaApi.Auth{}}}

      assert true == Api.signed_in?(name)

      refute_receive _
    end

    @tag :capture_log
    test "starts if credentials are valid", %{test: name} do
      :ok =
        start_api(name,
          tokens: nil,
          credentials: @valid_credentials
        )

      assert_receive {TeslaApi.AuthMock, {:login, "teslamate", "foo"}}
      assert_receive {AuthMock, {:save, %TeslaApi.Auth{}}}

      assert true == Api.signed_in?(name)

      refute_receive _
    end

    test "prioritizes tokens over credentials", %{test: name} do
      :ok = start_api(name, tokens: @valid_tokens, credentials: @valid_credentials)

      assert_receive {TeslaApi.AuthMock,
                      {:refresh, %TeslaApi.Auth{refresh_token: "$refresh", token: "$access"}}}

      assert_receive {AuthMock, {:save, %TeslaApi.Auth{}}}

      assert true == Api.signed_in?(name)

      refute_receive _
    end

    @tag :capture_log
    test "starts anyway if tokens are invalid ", %{test: name} do
      :ok = start_api(name, tokens: @invalid_tokens, credentials: nil)

      assert_receive {TeslaApi.AuthMock,
                      {:refresh, %TeslaApi.Auth{refresh_token: nil, token: nil}}}

      assert false == Api.signed_in?(name)

      refute_receive _
    end

    test "does not start if credentials are invalid", %{test: name} do
      assert {:error, {%TeslaApi.Error{env: nil, error: :induced_error, message: nil}, _}} =
               start_api(name, tokens: nil, credentials: @invalid_credentials)

      assert_receive {TeslaApi.AuthMock, {:login, nil, nil}}

      refute_receive _
    end
  end

  describe "sign_in/1" do
    test "allows delayed sign in", %{test: name} do
      :ok = start_api(name, tokens: nil, credentials: nil)

      assert false == Api.signed_in?(name)

      assert :ok = Api.sign_in(name, @valid_credentials)

      assert_receive {TeslaApi.AuthMock, {:login, "teslamate", "foo"}}
      assert_receive {AuthMock, {:save, %TeslaApi.Auth{}}}
      assert_receive {VehiclesMock, :restart}
      assert true == Api.signed_in?(name)

      refute_receive _
    end

    test "fails if already signed in", %{test: name} do
      :ok = start_api(name, tokens: @valid_tokens, credentials: nil)

      assert_receive {TeslaApi.AuthMock, {:refresh, %TeslaApi.Auth{}}}
      assert_receive {AuthMock, {:save, %TeslaApi.Auth{}}}
      assert true == Api.signed_in?(name)

      assert {:error, :already_signed_in} = Api.sign_in(name, @valid_credentials)

      refute_receive _
    end

    test "fails if the credentials are invalid", %{test: name} do
      :ok = start_api(name, tokens: nil, credentials: nil)

      assert false == Api.signed_in?(name)

      assert {:error, :induced_error} = Api.sign_in(name, @invalid_credentials)

      assert_receive {TeslaApi.AuthMock, {:login, nil, nil}}

      refute_receive _
    end
  end

  describe "Vehicle API" do
    test "get_vehicle/1", %{test: name} do
      :ok = start_api(name, tokens: @valid_tokens, credentials: nil)
      assert_receive {TeslaApi.AuthMock, {:refresh, _}}
      assert_receive {AuthMock, {:save, %TeslaApi.Auth{}}}

      assert {:error, :vehicle_not_found} = Api.get_vehicle(name, 0)
      assert_receive {TeslaApi.VehicleMock, {:list, %TeslaApi.Auth{}}}

      refute_receive _
    end

    test "get_vehicle_with_state/1", %{test: name} do
      :ok = start_api(name, tokens: @valid_tokens, credentials: nil)
      assert_receive {TeslaApi.AuthMock, {:refresh, _}}
      assert_receive {AuthMock, {:save, %TeslaApi.Auth{}}}

      assert {:ok, %TeslaApi.Vehicle{id: 0}} = Api.get_vehicle_with_state(name, 0)
      assert_receive {TeslaApi.VehicleMock, {:get_with_state, %TeslaApi.Auth{}, 0}}

      refute_receive _
    end

    test "list_vehicles/0", %{test: name} do
      :ok = start_api(name, tokens: @valid_tokens, credentials: nil)
      assert_receive {TeslaApi.AuthMock, {:refresh, _}}
      assert_receive {AuthMock, {:save, %TeslaApi.Auth{}}}

      assert {:ok, [%TeslaApi.Vehicle{}]} = Api.list_vehicles(name)
      assert_receive {TeslaApi.VehicleMock, {:list, %TeslaApi.Auth{}}}

      refute_receive _
    end
  end
end
