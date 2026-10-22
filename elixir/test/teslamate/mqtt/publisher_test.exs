defmodule TeslaMate.Mqtt.PublisherTest do
  use ExUnit.Case, async: false

  import Mock

  alias TeslaMate.Mqtt.Publisher

  setup do
    start_supervised!({Publisher, client_id: "test_client"})
    :ok
  end

  test "returns successful QoS 0 publishes immediately" do
    with_mock Tortoise311, publish: fn _id, _topic, _msg, _opts -> :ok end do
      assert :ok = Publisher.publish("test/topic", "value")
    end
  end

  test "returns successful QoS 1 publishes after acknowledgement" do
    parent = self()

    with_mock Tortoise311,
      publish: fn _id, _topic, _msg, _opts ->
        send(parent, :published)
        {:ok, :publish_ref}
      end do
      task = Task.async(fn -> Publisher.publish("test/topic", "value", qos: 1) end)

      assert_receive :published
      send(Publisher, {{Tortoise311, "test_client"}, :publish_ref, :ok})
      assert :ok = Task.await(task, :timer.seconds(11))
    end
  end

  test "returns QoS 1 acknowledgement errors" do
    parent = self()
    publisher = Process.whereis(Publisher)

    with_mock Tortoise311,
      publish: fn _id, _topic, _msg, _opts ->
        send(parent, :published)
        {:ok, :publish_ref}
      end do
      task = Task.async(fn -> Publisher.publish("test/topic", "value", qos: 1) end)

      assert_receive :published
      send(Publisher, {{Tortoise311, "test_client"}, :publish_ref, {:error, :timeout}})
      assert {:error, :timeout} = Task.await(task, :timer.seconds(1))
      assert Process.whereis(Publisher) == publisher
    end
  end

  test "expires unacknowledged QoS 1 publishes" do
    parent = self()
    publisher = Process.whereis(Publisher)

    with_mock Tortoise311,
      publish: fn _id, _topic, _msg, _opts ->
        send(parent, :published)
        {:ok, :publish_ref}
      end do
      task =
        Task.async(fn ->
          Publisher.publish("test/topic", "value", qos: 1, timeout: 20)
        end)

      assert_receive :published
      assert {:error, :timeout} = Task.await(task, :timer.seconds(1))
      assert %{refs: %{}} = :sys.get_state(Publisher)
      assert Process.whereis(Publisher) == publisher

      send(Publisher, {{Tortoise311, "test_client"}, :publish_ref, :ok})
      assert %{refs: %{}} = :sys.get_state(Publisher)
      assert Process.whereis(Publisher) == publisher
    end
  end

  test "clamps publish timeouts to the call budget" do
    parent = self()

    with_mock Tortoise311,
      publish: fn _id, _topic, _msg, opts ->
        send(parent, {:publish_timeout, Keyword.fetch!(opts, :timeout)})
        :ok
      end do
      assert :ok = Publisher.publish("test/topic", "value", timeout: :timer.minutes(1))
      assert_receive {:publish_timeout, 9_500}
    end
  end

  test "rejects invalid timeout values without publishing" do
    publisher = Process.whereis(Publisher)

    with_mock Tortoise311,
      publish: fn _id, _topic, _msg, _opts -> flunk("publish should not be called") end do
      for timeout <- [-1, "20", 1.0] do
        assert {:error, {:invalid_timeout, ^timeout}} =
                 Publisher.publish("test/topic", "value", timeout: timeout)
      end

      assert Process.whereis(Publisher) == publisher
    end
  end

  test "does not hide unexpected publisher exits" do
    parent = self()

    with_mock Tortoise311,
      publish: fn _id, _topic, _msg, _opts ->
        send(parent, :publishing)
        Process.sleep(:infinity)
      end do
      task = Task.async(fn -> catch_exit(Publisher.publish("test/topic", "value")) end)

      assert_receive :publishing
      Process.exit(Process.whereis(Publisher), :unexpected)

      assert {:unexpected, {GenServer, :call, _call}} = Task.await(task, :timer.seconds(1))
    end
  end

  test "keeps running when a QoS 0 publish fails" do
    publisher = Process.whereis(Publisher)

    with_mock Tortoise311,
      publish: fn _id, _topic, _msg, _opts -> {:error, :unknown_connection} end do
      assert {:error, :unknown_connection} = Publisher.publish("test/topic", "value")
      assert Process.whereis(Publisher) == publisher
    end
  end

  test "keeps running when a QoS 1 publish fails before acknowledgement" do
    publisher = Process.whereis(Publisher)

    with_mock Tortoise311,
      publish: fn _id, _topic, _msg, _opts -> {:error, :timeout} end do
      assert {:error, :timeout} = Publisher.publish("test/topic", "value", qos: 1)

      assert Process.whereis(Publisher) == publisher
    end
  end

  test "rejects invalid QoS values without publishing" do
    publisher = Process.whereis(Publisher)

    with_mock Tortoise311,
      publish: fn _id, _topic, _msg, _opts -> flunk("publish should not be called") end do
      for qos <- ["1", 1.0] do
        assert {:error, {:invalid_qos, ^qos}} =
                 Publisher.publish("test/topic", "value", qos: qos)
      end

      assert Process.whereis(Publisher) == publisher
    end
  end

  test "returns unexpected publish results without crashing" do
    publisher = Process.whereis(Publisher)

    with_mock Tortoise311, publish: fn _id, _topic, _msg, _opts -> :unexpected end do
      assert {:error, {:unexpected_publish_result, :unexpected}} =
               Publisher.publish("test/topic", "value")

      assert Process.whereis(Publisher) == publisher
    end
  end

  test "returns an error when the publisher is unavailable" do
    assert :ok = stop_supervised(Publisher)
    assert {:error, :publisher_unavailable} = Publisher.publish("test/topic", "value")
  end

  test "ignores acknowledgements for unknown references and clients" do
    publisher = Process.whereis(Publisher)

    send(Publisher, {{Tortoise311, "test_client"}, :unknown_ref, :ok})
    send(Publisher, {{Tortoise311, "other_client"}, :unknown_ref, :ok})
    :sys.get_state(Publisher)

    assert Process.whereis(Publisher) == publisher
  end
end
