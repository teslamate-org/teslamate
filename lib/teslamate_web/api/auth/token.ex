defmodule TeslaMateWeb.Api.Auth.Token do
  use Joken.Config

  @token_ttl 24 * 60 * 60

  def token_config do
    default_claims(default_exp: @token_ttl)
    |> add_claim("sub", nil, &is_binary/1)
  end

  def generate_jwt do
    config = Application.get_env(:teslamate, :api)
    secret = Keyword.fetch!(config, :jwt_secret)
    signer = Joken.Signer.create("HS256", secret)

    exp = DateTime.utc_now() |> DateTime.add(@token_ttl, :second) |> DateTime.to_unix()
    claims = %{"sub" => "api_user", "exp" => exp}

    case Joken.generate_and_sign(token_config(), claims, signer) do
      {:ok, token, _claims} -> {:ok, token, exp}
      {:error, reason} -> {:error, reason}
    end
  end

  def verify_jwt(token) do
    config = Application.get_env(:teslamate, :api)
    secret = Keyword.fetch!(config, :jwt_secret)
    signer = Joken.Signer.create("HS256", secret)

    Joken.verify_and_validate(token_config(), token, signer)
  end
end
