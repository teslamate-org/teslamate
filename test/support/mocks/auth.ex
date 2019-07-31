defmodule AuthMock do
  use GenServer

  defstruct [:pid, :credentials, :tokens]
  alias __MODULE__, as: State

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def get_credentials(name), do: GenServer.call(name, :get_credentials)
  def get_tokens(name), do: GenServer.call(name, :get_tokens)
  def save(name, auth), do: GenServer.call(name, {:save, auth})

  # Callbacks

  @impl true
  def init(opts) do
    {:ok,
     %State{
       pid: Keyword.fetch!(opts, :pid),
       credentials: Keyword.fetch!(opts, :credentials),
       tokens: Keyword.fetch!(opts, :tokens)
     }}
  end

  @impl true
  def handle_call(:get_credentials, _from, state) do
    {:reply, state.credentials, state}
  end

  def handle_call(:get_tokens, _from, state) do
    {:reply, state.tokens, state}
  end

  def handle_call({:save, _auth} = event, _from, %State{pid: pid} = state) do
    send(pid, {AuthMock, event})
    {:reply, :ok, state}
  end
end
