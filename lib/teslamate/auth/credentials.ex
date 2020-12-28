defmodule TeslaMate.Auth.Credentials do
  use Ecto.Schema
  import Ecto.Changeset

  schema "" do
    field :email, :string
    field :password, :string
    field :use_legacy_auth, :boolean, default: false
  end

  @doc false
  def changeset(credentials, attrs) do
    credentials
    |> cast(attrs, [:email, :password, :use_legacy_auth])
    |> validate_required([:email, :password])
  end
end
