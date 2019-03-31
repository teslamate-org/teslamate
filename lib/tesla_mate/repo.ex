defmodule TeslaMate.Repo do
  use Ecto.Repo,
    otp_app: :tesla_mate,
    adapter: Ecto.Adapters.Postgres
end
