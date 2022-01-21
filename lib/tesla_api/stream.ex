defmodule TeslaApi.Stream do
  use WebSockex

  require Logger
  alias TeslaApi.Auth
  alias __MODULE__.Data

  defmodule State do
    defstruct auth: nil,
              vehicle_id: nil,
              timer: nil,
              receiver: &IO.inspect/1,
              last_data: nil,
              timeouts: 0,
              disconnects: 0
  end

  @columns ~w(speed odometer soc elevation est_heading est_lat est_lng power shift_state range
              est_range heading)a

  @cacerts CAStore.file_path()
           |> File.read!()
           |> :public_key.pem_decode()
           |> Enum.map(fn {_, cert, _} -> cert end)

  def start_link(args) do
    state = %State{
      receiver: Keyword.get(args, :receiver, &Logger.debug(inspect(&1))),
      vehicle_id: Keyword.fetch!(args, :vehicle_id),
      auth: Keyword.fetch!(args, :auth)
    }

    endpoint_url =
      case Auth.region(state.auth) do
        :chinese -> "wss://streaming.vn.cloud.tesla.cn/streaming/"
        _global -> "wss://streaming.vn.teslamotors.com/streaming/"
      end

    WebSockex.start_link(endpoint_url, __MODULE__, state,
      socket_connect_timeout: :timer.seconds(15),
      socket_recv_timeout: :timer.seconds(30),
      name: :"stream_#{state.vehicle_id}",
      cacerts: @cacerts,
      insecure: false,
      async: true
    )
  end

  def disconnect(pid) do
    WebSockex.cast(pid, :disconnect)
  end

  @impl true
  def handle_cast(:disconnect, %State{vehicle_id: vid} = state) do
    send(self(), :exit)
    {:reply, frame!(%{msg_type: "data:unsubscribe", tag: "#{vid}"}), state}
  end

  @impl true
  def handle_connect(_conn, state) do
    Logger.debug("Connection established")
    send(self(), :subscribe)
    {:ok, state}
  end

  @impl true
  def handle_info(:subscribe, %State{auth: %Auth{token: token}, vehicle_id: vid} = state) do
    Logger.debug("Subscribing …")

    cancel_timer(state.timer)
    ms = exp_backoff_ms(state.timeouts, min_seconds: 10, max_seconds: 30)
    timer = Process.send_after(self(), :timeout, ms)

    connect_message = %{
      msg_type: "data:subscribe_oauth",
      token: token,
      value: Enum.join(@columns, ","),
      tag: "#{vid}"
    }

    {:reply, frame!(connect_message), %State{state | timer: timer}}
  end

  def handle_info(:timeout, %State{timeouts: t, receiver: receiver} = state) do
    Logger.debug("Stream.Timeout / #{inspect(t)}")

    if match?(%State{last_data: %Data{}}, state) and rem(t, 10) == 4 do
      receiver.(:inactive)
    end

    {:close, %State{state | timeouts: t + 1}}
  end

  def handle_info({:ssl, _, _} = msg, state) do
    Logger.warn("Received unexpected message: #{inspect(msg)}")
    {:ok, state}
  end

  def handle_info(:exit, _state) do
    exit(:normal)
  end

  @impl true
  def handle_frame({_type, msg}, %State{vehicle_id: vid} = state) do
    tag = to_string(vid)

    cancel_timer(state.timer)
    timer = Process.send_after(self(), :timeout, :timer.seconds(30))
    state = %State{state | timer: timer}

    case Jason.decode(msg) do
      {:ok, %{"msg_type" => "control:hello", "connection_timeout" => t}} ->
        Logger.debug("control:hello – #{t}")
        {:ok, state}

      {:ok, %{"msg_type" => "data:update", "tag" => ^tag, "value" => data}}
      when is_binary(data) ->
        data =
          Enum.zip([:time | @columns], String.split(data, ","))
          |> Enum.into(%{})
          |> Data.into!()

        state.receiver.(data)

        {:ok, %State{state | last_data: data, timeouts: 0, disconnects: 0}}

      {:ok, %{"msg_type" => "data:error", "tag" => ^tag, "error_type" => "vehicle_disconnected"}} ->
        case state.disconnects do
          d when d != 0 and rem(d, 10) == 0 ->
            Logger.warning("Too many disconnects from streaming API")

            cancel_timer(state.timer)
            state.receiver.(:too_many_disconnects)

            {:ok, %State{state | disconnects: d + 1}}

          d ->
            ms =
              case state do
                %State{last_data: %Data{shift_state: s}} when s in ~w(P D N R) ->
                  exp_backoff_ms(d, base: 1.3, max_seconds: 8)

                %State{} ->
                  exp_backoff_ms(d, min_seconds: 15, max_seconds: 30)
              end

            cancel_timer(state.timer)
            timer = Process.send_after(self(), :subscribe, ms)

            {:ok, %State{state | timer: timer, disconnects: d + 1}}
        end

      {:ok,
       %{"msg_type" => "data:error", "tag" => ^tag, "error_type" => "vehicle_error", "value" => v}} ->
        Logger.error("Vehicle Error: #{v}")
        {:ok, state}

      {:ok, %{"msg_type" => "data:error", "tag" => ^tag, "error_type" => "client_error"} = msg} ->
        case msg do
          %{"value" => "owner_api error:" <> _ = error} ->
            Logger.warn("Streaming API Client Error: #{error}")
            {:close, state}

          _ ->
            raise "Client Error: #{inspect(msg)}"
        end

      {:ok, %{"msg_type" => "data:error", "tag" => ^tag, "error_type" => type, "value" => v}} ->
        Logger.error("Error #{inspect(type)}: #{v}")
        {:ok, state}

      {:ok, msg} ->
        Logger.warning("Unkown Message: #{inspect(msg, pretty: true)}")
        {:ok, state}

      {:error, reason} ->
        Logger.error("Invalid data frame: #{inspect(reason)}")
        {:ok, state}
    end
  end

  @impl true
  def handle_disconnect(%{reason: reason, attempt_number: n}, state) when is_number(n) do
    cancel_timer(state.timer)

    case reason do
      {:local, :normal} ->
        Logger.debug(
          "Connection was closed (a:#{n}|t:#{state.timeouts}|d:#{state.disconnects}). Reconnecting …"
        )

        {:reconnect, state}

      {:remote, :closed} ->
        Logger.warning("WebSocket disconnected. Reconnecting …")

        n
        |> exp_backoff_ms(max_seconds: 10)
        |> Process.sleep()

        {:reconnect, %State{state | last_data: nil}}

      %WebSockex.ConnError{} = e ->
        Logger.warning("Disconnected! #{Exception.message(e)} | #{n}")

        n
        |> exp_backoff_ms(min_seconds: 1)
        |> Process.sleep()

        {:reconnect, state}

      %WebSockex.RequestError{} = e ->
        Logger.warning("Disconnected! #{Exception.message(e)} | #{n}")

        n
        |> exp_backoff_ms(min_seconds: 1)
        |> Process.sleep()

        {:reconnect, state}
    end
  end

  @impl true
  def terminate(:normal, _state), do: :ok

  def terminate(reason, _state) do
    # https://github.com/Azolo/websockex/issues/51
    with {exception, stacktrace} <- reason, true <- Exception.exception?(exception) do
      Logger.error(fn -> Exception.format(:error, exception, stacktrace) end)
    else
      _ -> Logger.error("Terminating: #{inspect(reason)}")
    end

    :ok
  end

  ## Private

  defp frame!(data) when is_map(data), do: {:text, Jason.encode!(data)}

  defp exp_backoff_ms(n, opts) when is_number(n) and 0 <= n do
    base = Keyword.get(opts, :base, 2)
    min = Keyword.get(opts, :min_seconds, 0)
    max = Keyword.get(opts, :max_seconds, 30)

    :math.pow(base, n) |> min(max) |> max(min) |> round() |> :timer.seconds()
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref) when is_reference(ref), do: Process.cancel_timer(ref)
end
