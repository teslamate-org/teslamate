Application.load(:teslamate)

for app <- Application.spec(:teslamate, :applications) do
  {:ok, _} = Application.ensure_all_started(app)
end

TeslaMate.Repo.start_link()

ExUnit.start(assert_receive_timeout: 200)
