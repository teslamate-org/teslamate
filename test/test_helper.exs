Application.load(:teslamate)

for app <- Application.spec(:teslamate, :applications) do
  {:ok, _} = Application.ensure_all_started(app)
end

TeslaMate.Repo.start_link()

%{start: {m, f, [name, _opts]}} = TeslaMate.Locations.child_spec([])
apply(m, f, [name, [limit: 1]])

ExUnit.start(assert_receive_timeout: 300)
