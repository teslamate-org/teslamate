defmodule TeslaMate.AuthTest do
  use TeslaMate.DataCase

  alias TeslaMate.Auth

  setup do
    start_supervised!(TeslaMate.Vault)
    :ok
  end

  describe "tokens" do
    @valid_attrs %{refresh_token: "some refresh token", token: "some access token"}
    @update_attrs %{
      refresh_token: "some updated refresh token",
      token: "some updated access token"
    }
    @invalid_attrs %{refresh_token: nil, token: nil}

    test "save/1 with valid data creates or updats the tokens" do
      assert Auth.get_tokens() == nil

      assert :ok = Auth.save(@valid_attrs)
      assert tokens = Auth.get_tokens()
      assert tokens.refresh == "some refresh token"
      assert tokens.access == "some access token"

      assert :ok = Auth.save(@update_attrs)
      assert tokens = Auth.get_tokens()
      assert tokens.refresh == "some updated refresh token"
      assert tokens.access == "some updated access token"
    end

    test "save/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{} = changeset} = Auth.save(@invalid_attrs)

      assert %{refresh: ["can't be blank"], access: ["can't be blank"]} ==
               errors_on(changeset)
    end
  end
end
