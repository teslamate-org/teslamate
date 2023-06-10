defmodule TeslaMate.Auth.Tokens do
  use Ecto.Schema

  import Ecto.Changeset

  alias TeslaMate.Vault.Encrypted
  alias TeslaMate.Log.Car

  schema "tokens" do
    field :refresh, Encrypted.Binary, redact: true
    field :access, Encrypted.Binary, redact: true
    field :account_email, :string

    has_many :cars, Car, foreign_key: :tokens_id

    timestamps()
  end

  @doc false
  def changeset(tokens, attrs) do
    tokens
    |> cast(attrs, [:access, :refresh, :account_email])
    |> validate_required([:access, :refresh, :account_email])
  end
end
