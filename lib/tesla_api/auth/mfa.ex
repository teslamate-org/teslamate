defmodule TeslaApi.Auth.MFA do
  import TeslaApi.Auth, only: [get: 2, post: 3]

  alias TeslaApi.{Error}

  def list_devices(transaction_id, headers) do
    params = [transaction_id: transaction_id]

    case get("/oauth2/v3/authorize/mfa/factors", query: params, headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: %{"data" => devices}}} ->
        {:ok, devices}

      error ->
        Error.into(error, :mfa_factor_lookup_failed)
    end
  end

  def verify_passcode(device_id, mfa_passcode, transaction_id, headers) do
    params = [transaction_id: transaction_id]

    data = %{
      transaction_id: transaction_id,
      factor_id: device_id,
      passcode: mfa_passcode
    }

    case post("/oauth2/v3/authorize/mfa/verify", data, headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: body} = env} ->
        case body do
          %{"data" => %{"approved" => true, "valid" => true}} ->
            case get("/oauth2/v3/authorize", query: params, headers: headers) do
              {:ok, %Tesla.Env{status: 302} = env} ->
                {:ok, env}

              error ->
                Error.into(error)
            end

          %{"data" => %{}} ->
            error = %Error{
              reason: :mfa_passcode_invalid,
              message: "Incorrect verfification code",
              env: env
            }

            {:error, error}
        end

      error ->
        Error.into(error, :mfa_verification_failed)
    end
  end
end
