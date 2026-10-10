defmodule TeslaMate.Repo.Migrations.EnableStreaming do
  use Ecto.Migration

  alias TeslaMate.Settings.CarSettings
  alias TeslaMate.Repo

  def up, do: Repo.update_all(CarSettings, set: [use_streaming_api: true])
  def down, do: :ok
end
