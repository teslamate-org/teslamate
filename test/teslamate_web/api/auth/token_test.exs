defmodule TeslaMateWeb.Api.Auth.TokenTest do
  use TeslaMateWeb.ApiCase

  alias TeslaMateWeb.Api.Auth.Token

  describe "generate_jwt/0" do
    test "generates a valid JWT that can be verified" do
      assert {:ok, jwt, exp} = Token.generate_jwt()
      assert is_binary(jwt)
      assert is_integer(exp)

      assert {:ok, claims} = Token.verify_jwt(jwt)
      assert claims["sub"] == "api_user"
      assert claims["exp"] == exp
    end

    test "generates JWT with ~24h expiration" do
      {:ok, _jwt, exp} = Token.generate_jwt()
      now = DateTime.utc_now() |> DateTime.to_unix()

      # Expiration should be roughly 24 hours from now (allow 5s tolerance)
      assert_in_delta exp, now + 24 * 60 * 60, 5
    end
  end

  describe "verify_jwt/1" do
    test "rejects garbage tokens" do
      assert {:error, _reason} = Token.verify_jwt("not.a.valid.jwt")
    end

    test "rejects empty string" do
      assert {:error, _reason} = Token.verify_jwt("")
    end

    test "rejects token signed with wrong secret" do
      wrong_signer = Joken.Signer.create("HS256", "wrong_secret_that_is_long_enough_32_bytes!")
      claims = %{"sub" => "api_user", "exp" => DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_unix()}

      {:ok, bad_token, _claims} =
        Joken.generate_and_sign(Token.token_config(), claims, wrong_signer)

      assert {:error, _reason} = Token.verify_jwt(bad_token)
    end

    test "rejects expired token" do
      config = Application.get_env(:teslamate, :api)
      secret = Keyword.fetch!(config, :jwt_secret)
      signer = Joken.Signer.create("HS256", secret)

      expired_exp = DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_unix()
      claims = %{"sub" => "api_user", "exp" => expired_exp}

      {:ok, expired_token, _claims} =
        Joken.generate_and_sign(Token.token_config(), claims, signer)

      assert {:error, _reason} = Token.verify_jwt(expired_token)
    end
  end
end
