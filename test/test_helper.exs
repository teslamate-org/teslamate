Application.load(:teslamate)

for app <- Application.spec(:teslamate, :applications) do
  {:ok, _} = Application.ensure_all_started(app)
end

# :ok = Application.ensure_all_started(TeslaMate.Repo)

TeslaMate.Repo.start_link()

ExUnit.start(assert_receive_timeout: 200)

# Ecto.Adapters.SQL.Sandbox.mode(TeslaMate.Repo, :manual)
