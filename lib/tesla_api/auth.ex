defmodule TeslaApi.Auth do
  require Logger

  alias TeslaApi.{Auth, Error}

  defstruct [:token, :type, :expires_in, :refresh_token, :created_at]

  @client_id "81527cff06843c8634fdc09e8ac0abefb46ac849f38fe1e431c2ef2106796384"
  @client_secret "c7257eb71a564034f9419ee651c7d0e5f7aa6bfbd18bafb5c5c033b093bb2fa3"

  def login(email, password) do
    __MODULE__.MFA.login(email, password)
  rescue
    e in RuntimeError ->
      if e.message == "MFA passcode required" do
        Logger.warn("Tesla Account requires MFA passcode. Using legacy login …")
        legacy_login(email, password)
      else
        reraise e, __STACKTRACE__
      end
  end

  def legacy_login(email, password) do
    data = %{
      grant_type: "password",
      client_id: @client_id,
      client_secret: @client_secret,
      email: email,
      password: password
    }

    TeslaApi.post("/oauth/token", data)
    |> handle_response()
  end

  def refresh(%Auth{token: token, refresh_token: refresh_token}) do
    data = %{
      grant_type: "refresh_token",
      client_id: @client_id,
      client_secret: @client_secret,
      refresh_token: refresh_token
    }

    TeslaApi.post("/oauth/token", data, opts: [access_token: token])
    |> handle_response()
  end

  def revoke(%Auth{token: token}) do
    TeslaApi.post("/oauth/revoke", %{token: token}, opts: [access_token: token])
    |> handle_response()
  end

  defp handle_response(response) do
    case response do
      {:ok, %Tesla.Env{status: 200, body: body}} when body == %{} ->
        :ok

      {:ok, %Tesla.Env{status: 200, body: %{"response" => true}}} ->
        :ok

      {:ok, %Tesla.Env{status: 200, body: body}} when is_map(body) ->
        auth = %__MODULE__{
          token: body["access_token"],
          type: body["token_type"],
          expires_in: body["expires_in"],
          refresh_token: body["refresh_token"],
          created_at: body["created_at"]
        }

        {:ok, auth}

      {:ok, %Tesla.Env{status: 401} = e} ->
        error = %Error{
          reason: :authentication_failure,
          message: "Failed to authenticate.",
          env: e
        }

        {:error, error}

      {:ok, %Tesla.Env{} = e} ->
        {:error, %Error{reason: :unknown, message: "An unknown error has occurred.", env: e}}

      {:error, %{reason: reason} = e} ->
        error = %Error{
          reason: :unknown,
          message: "An unknown error has occurred: #{inspect(reason)}",
          env: e
        }

        {:error, error}
    end
  end
end
