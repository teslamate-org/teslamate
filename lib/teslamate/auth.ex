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
    account_email = Application.get_env(:teslamate, :account_email)
    if account_email == nil do
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
    else
      Repo.get_by(Tokens, account_email: account_email)
    end
  end

  def save(%{token: access, refresh_token: refresh, account_email: account_email}) do
    attrs = %{access: access, refresh: refresh, account_email: account_email}

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
