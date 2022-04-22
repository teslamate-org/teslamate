defmodule TeslaMate.Auth.Tokens do
  use Ecto.Schema

  import Ecto.Changeset

  alias TeslaMate.Vault.Encrypted

  schema "tokens" do
    field :refresh, Encrypted.Binary, redact: true
    field :access, Encrypted.Binary, redact: true

    timestamps()
  end

  @doc false
  def changeset(tokens, attrs) do
    tokens
    |> cast(attrs, [:access, :refresh])
    |> validate_required([:access, :refresh])
  end
end
