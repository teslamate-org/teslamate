Application.load(:tesla_mate)

for app <- Application.spec(:tesla_mate, :applications) do
  {:ok, _} = Application.ensure_all_started(app)
end

# :ok = Application.ensure_all_started(TeslaMate.Repo)

TeslaMate.Repo.start_link()

ExUnit.start()

# Ecto.Adapters.SQL.Sandbox.mode(TeslaMate.Repo, :manual)
