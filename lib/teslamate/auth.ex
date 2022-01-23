defmodule TeslaMate.Auth do
  @moduledoc """
  The Auth context.
  """

  import Ecto.Query, warn: false
  require Logger

  alias TeslaMate.Repo

  ### Tokens

  alias TeslaMate.Auth.Tokens

  def change_tokens(attrs \\ %{}) do
    %Tokens{} |> Tokens.changeset(attrs)
  end

  def can_decrypt_tokens? do
    case get_tokens() do
      %Tokens{} = tokens ->
        is_binary(tokens.access) and is_binary(tokens.refresh)

      nil ->
        true
    end
  end

  def get_tokens do
    case Repo.all(Tokens) do
      [%Tokens{} = tokens] ->
        tokens

      [_ | _] = tokens ->
        raise """
        Found #{length(tokens)} token pairs!

        Make sure that there is no more than ONE token pair in the table 'tokens'.
        """

      [] ->
        nil
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
