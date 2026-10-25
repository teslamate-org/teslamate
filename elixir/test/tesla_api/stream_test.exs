defmodule TeslaApi.StreamTest do
  # Changes TESLA_WSS_HOST for the whole VM.
  use ExUnit.Case, async: false

  alias TeslaApi.{Auth, Stream}

  @moduletag :capture_log

  describe "start_link/1" do
    setup do
      wss_host = System.get_env("TESLA_WSS_HOST")
      # Nothing listens on port 1: every connection attempt is refused.
      System.put_env("TESLA_WSS_HOST", "ws://127.0.0.1:1")

      on_exit(fn ->
        if wss_host,
          do: System.put_env("TESLA_WSS_HOST", wss_host),
          else: System.delete_env("TESLA_WSS_HOST")
      end)
    end

    test "keeps retrying, without exiting its caller, when the first connection fails" do
      Process.flag(:trap_exit, true)

      assert {:ok, pid} =
               Stream.start_link(
                 auth: %Auth{token: "qts-token"},
                 vehicle_id: 4242,
                 receiver: fn _ -> :ok end
               )

      refute_receive {:EXIT, ^pid, _reason}, 1_000
      assert Process.alive?(pid)

      Process.exit(pid, :kill)
      assert_receive {:EXIT, ^pid, :killed}
    end
  end

  describe "handle_disconnect/2" do
    # WebSockex.close_reason/0 reasons the other clauses do not cover.
    for reason <- [
          {:remote, 1001, "going away"},
          {:remote, :normal},
          {:local, 1002, "protocol error"},
          {:error, %WebSockex.ConnError{original: :closed}}
        ] do
      test "reconnects after #{inspect(reason)}" do
        assert {:reconnect, %Stream.State{}} =
                 Stream.handle_disconnect(
                   %{reason: unquote(Macro.escape(reason)), attempt_number: 0, conn: nil},
                   %Stream.State{}
                 )
      end
    end
  end

  describe "handle_info/2" do
    test "ignores socket messages of a previous connection" do
      for msg <- [{:ssl_closed, make_ref()}, {:ssl_error, make_ref(), :closed}] do
        assert {:ok, %Stream.State{}} = Stream.handle_info(msg, %Stream.State{})
      end
    end
  end
end
