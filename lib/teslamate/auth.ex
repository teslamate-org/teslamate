defmodule TeslaMate.Auth do
  @moduledoc """
  The Auth context.
  """

  import Ecto.Query, warn: false
  alias TeslaMate.Repo

  ### Credentials

  alias TeslaMate.Auth.Credentials

  def get_credentials do
    opts = Application.fetch_env!(:teslamate, :tesla_auth)

    with username when not is_nil(username) <- Keyword.get(opts, :username),
         password when not is_nil(password) <- Keyword.get(opts, :password) do
      %Credentials{email: username, password: password}
    else
      _ -> nil
    end
  end

  def change_credentials(attrs \\ %{}) do
    %Credentials{} |> Credentials.changeset(attrs)
  end

  ### Tokens

  alias TeslaMate.Auth.Tokens

  def get_tokens do
    case Repo.all(Tokens) do
      [tokens] -> tokens
      [] -> nil
    end
  end

  def save(%{token: access, refresh_token: refresh}) do
    attrs = %{access: access, refresh: refresh}

    maybe_created_or_updated =
      case get_tokens() do
        nil -> create_tokens(attrs)
        tokens -> update_tokens(tokens, attrs)
      end

    with {:ok, _tokens} <- maybe_created_or_updated do
      :ok
    end
  end

  defp create_tokens(attrs) do
    %Tokens{}
    |> Tokens.changeset(attrs)
    |> Repo.insert()
  end

  defp update_tokens(%Tokens{} = tokens, attrs) do
    tokens
    |> Tokens.changeset(attrs)
    |> Repo.update()
  end
end
