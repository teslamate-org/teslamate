defmodule TeslaMate.Repo do
  use Ecto.Repo,
    otp_app: :teslamate,
    adapter: Ecto.Adapters.Postgres
end
