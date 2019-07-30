defmodule TeslaMate.Auth.Credentials do
  use Ecto.Schema
  import Ecto.Changeset

  schema "" do
    field :email, :string
    field :password, :string
  end

  @doc false
  def changeset(credentials, attrs) do
    credentials
    |> cast(attrs, [:email, :password])
    |> validate_required([:email, :password])
  end
end
