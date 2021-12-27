defmodule TeslaMate.UpdaterTest do
  use TeslaMate.DataCase, async: true

  alias TeslaMate.Updater
  import Mock

  defmodule HTTPMocck do
    def vsn(tag) do
      json(%{"tag_name" => tag, "prerelease" => false, "draft" => false})
    end

    def json(data) do
      response({:ok, %Tesla.Env{status: 200, body: data}})
    end

    def response(resp) do
      [
        {Tesla.Adapter.Finch, [],
         call: fn %Tesla.Env{} = env, _opts ->
           assert env.url == "https://api.github.com/repos/adriankumpf/teslamate/releases/latest"
           resp
         end}
      ]
    end
  end

  defp create_updater(version) do
    {:ok, updater} = Updater.init(version: version)

    updater
  end

  defp create_updater_and_check_for_updates(version) do
    {:ok, updater} = Updater.init(version: version)

    updater
    |> Updater.check_for_updates()
  end

  test "informs if an update is available" do
    with_mocks HTTPMocck.vsn("v5.1.2") do
      ## current_version > new_version
      updater = create_updater_and_check_for_updates("5.1.3-dev")
      assert nil == Updater.get_update(updater)

      ## current_version == new_version
      updater = create_updater_and_check_for_updates("5.1.2")
      assert nil == Updater.get_update(updater)

      ## current_version < new_version
      updater = create_updater_and_check_for_updates("4.99.0")
      assert "5.1.2" == Updater.get_update(updater)
    end
  end

  test "returns early even though update check is still in progress" do
    with_mocks [{Tesla.Adapter.Finch, [], call: fn _, _ -> Process.sleep(1_000_000) end}] do
      updater = create_updater("1.0.0")
      assert nil == Updater.get_update(updater)
    end
  end

  @tag :capture_log
  test "handles invalid tags" do
    with_mocks HTTPMocck.vsn("2.0.0") do
      updater = create_updater("1.0.0")
      assert nil == Updater.get_update(updater)
    end
  end

  @tag :capture_log
  test "handles invalid json" do
    with_mocks HTTPMocck.json(%{"foo" => "bar"}) do
      updater = create_updater("1.0.0")
      assert nil == Updater.get_update(updater)
    end
  end

  @tag :capture_log
  test "handles HTTP errors" do
    with_mocks HTTPMocck.response({:ok, %Tesla.Env{status: 404}}) do
      updater = create_updater("1.0.0")
      assert nil == Updater.get_update(updater)
    end

    with_mocks HTTPMocck.response({:error, :timeout}) do
      updater = create_updater("1.0.0")
      assert nil == Updater.get_update(updater)
    end
  end

  test "handles prereleases and drafts" do
    with_mocks HTTPMocck.json(%{"tag_name" => "v99.0.0", "prerelease" => true, "draft" => false}) do
      updater = create_updater("1.0.0")
      assert nil == Updater.get_update(updater)
    end

    with_mocks HTTPMocck.json(%{"tag_name" => "v99.0.0", "prerelease" => false, "draft" => true}) do
      updater = create_updater("1.0.0")
      assert nil == Updater.get_update(updater)
    end
  end
end
