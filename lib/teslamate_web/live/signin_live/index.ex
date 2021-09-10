defmodule TeslaMateWeb.SignInLive.Index do
  use TeslaMateWeb, :live_view

  import Core.Dependency, only: [call: 3]
  alias TeslaMate.{Auth, Api}

  defmodule State.Credentials do
    import Ecto.Changeset

    defstruct [:changeset]

    def init, do: %__MODULE__{changeset: credentials_changeset()}

    def change(%__MODULE__{} = t, credentials) do
      changeset =
        credentials
        |> credentials_changeset()
        |> Map.put(:action, :update)

      %__MODULE__{t | changeset: changeset}
    end

    defp credentials_changeset(attrs \\ %{}) do
      {%{}, %{email: :string, password: :string}}
      |> cast(attrs, [:email, :password])
      |> validate_required([:email, :password])
    end
  end

  defmodule State.Captcha do
    import Ecto.Changeset

    defstruct [:changeset, :captcha, :callback, :prev_state]

    def init(captcha, callback, prev_state) do
      %__MODULE__{
        changeset: captcha_changeset(),
        captcha: captcha,
        callback: callback,
        prev_state: prev_state
      }
    end

    def change(%__MODULE__{} = t, catpcha) do
      changeset =
        catpcha
        |> captcha_changeset()
        |> Map.put(:action, :update)

      %__MODULE__{t | changeset: changeset}
    end

    defp captcha_changeset(attrs \\ %{}) do
      {%{}, %{code: :string}}
      |> cast(attrs, [:code])
      |> validate_required([:code])
    end
  end

  defmodule State.MFA do
    import Ecto.Changeset

    defstruct [:changeset, :devices, :callback]

    def init(devices, callback) do
      %__MODULE__{changeset: mfa_changeset(), devices: devices, callback: callback}
    end

    def change(%__MODULE__{} = t, mfa) do
      changeset =
        mfa
        |> mfa_changeset()
        |> Map.put(:action, :update)

      %__MODULE__{t | changeset: changeset}
    end

    defp mfa_changeset(attrs \\ %{}) do
      {%{}, %{passcode: :string, device_id: :string}}
      |> cast(attrs, [:passcode, :device_id])
      |> validate_required([:passcode, :device_id])
      |> validate_length(:passcode, is: 6)
      |> validate_format(:passcode, ~r/\d{6}/)
    end
  end

  defmodule State.Tokens do
    defstruct [:changeset]

    def init, do: %__MODULE__{changeset: Auth.change_tokens()}

    def change(%__MODULE__{} = t, tokens) do
      changeset =
        tokens
        |> Auth.change_tokens()
        |> Map.put(:action, :update)

      %__MODULE__{t | changeset: changeset}
    end
  end

  @impl true
  def mount(_params, %{"locale" => locale}, socket) do
    if connected?(socket), do: Gettext.put_locale(locale)

    assigns = %{
      api: get_api(socket),
      page_title: gettext("Sign in"),
      callback: fn _, _, _ -> :error end,
      error: nil,
      task: nil,
      state: State.Credentials.init()
    }

    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      case params["use_api_tokens"] do
        "true" -> assign(socket, state: State.Tokens.init())
        "false" -> assign(socket, state: State.Credentials.init())
        _ -> socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "validate",
        %{"credentials" => credentials},
        %{assigns: %{state: %State.Credentials{}}} = socket
      ) do
    state = State.Credentials.change(socket.assigns.state, credentials)
    {:noreply, assign(socket, state: state, error: nil)}
  end

  def handle_event(
        "validate",
        %{"tokens" => tokens},
        %{assigns: %{state: %State.Tokens{}}} = socket
      ) do
    state = State.Tokens.change(socket.assigns.state, tokens)
    {:noreply, assign(socket, state: state, error: nil)}
  end

  def handle_event(
        "validate",
        %{"captcha" => captcha},
        %{assigns: %{state: %State.Captcha{}}} = socket
      ) do
    state = State.Captcha.change(socket.assigns.state, captcha)
    {:noreply, assign(socket, state: state, error: nil)}
  end

  def handle_event(
        "validate",
        %{"mfa" => mfa},
        %{assigns: %{state: %State.MFA{}}} = socket
      ) do
    state = State.MFA.change(socket.assigns.state, mfa)

    task =
      if state.changeset.valid? do
        %{passcode: passcode, device_id: device_id} =
          Ecto.Changeset.apply_changes(state.changeset)

        Task.async(fn ->
          state.callback.(device_id, passcode)
        end)
      end

    {:noreply, assign(socket, state: state, task: task, error: nil)}
  end

  def handle_event("sign_in", _, %{assigns: %{state: %State.Credentials{} = state}} = socket) do
    credentials = Ecto.Changeset.apply_changes(state.changeset)

    task =
      Task.async(fn ->
        call(socket.assigns.api, :sign_in, [{credentials.email, credentials.password}])
      end)

    {:noreply, assign(socket, task: task)}
  end

  def handle_event("sign_in", _, %{assigns: %{state: %State.Tokens{} = state}} = socket) do
    tokens = Ecto.Changeset.apply_changes(state.changeset)

    task =
      Task.async(fn ->
        call(socket.assigns.api, :sign_in, [tokens])
      end)

    {:noreply, assign(socket, task: task)}
  end

  def handle_event("sign_in", _, %{assigns: %{state: %State.Captcha{} = state}} = socket) do
    %{code: captcha_code} = Ecto.Changeset.apply_changes(state.changeset)

    task =
      Task.async(fn ->
        state.callback.(captcha_code)
      end)

    {:noreply, assign(socket, task: task)}
  end

  def handle_event("use_api_tokens", _params, socket) do
    path = Routes.live_path(socket, __MODULE__, %{use_api_tokens: true})

    socket =
      socket
      |> push_patch(to: path)
      |> assign(error: nil)

    {:noreply, socket}
  end

  def handle_event("use_credentials", _params, socket) do
    path = Routes.live_path(socket, __MODULE__, %{use_api_tokens: false})

    socket =
      socket
      |> push_patch(to: path)
      |> assign(error: nil)

    {:noreply, socket}
  end

  @impl true
  def handle_info({ref, result}, %{assigns: %{task: %Task{ref: ref}}} = socket) do
    Process.demonitor(ref, [:flush])

    case result do
      :ok ->
        Process.sleep(250)
        {:noreply, redirect_to_carlive(socket)}

      {:ok, {:captcha, captcha, callback}} ->
        credentials_state =
          case socket.assigns.state do
            %State.Credentials{} = credentials_state -> credentials_state
            %State.Captcha{} = captcha_state -> captcha_state.prev_state
          end

        state = State.Captcha.init(captcha, callback, credentials_state)
        {:noreply, assign(socket, state: state, task: nil)}

      {:ok, {:mfa, devices, callback}} ->
        devices = Enum.map(devices, fn %{"name" => name, "id" => id} -> {name, id} end)
        state = State.MFA.init(devices, callback)
        {:noreply, assign(socket, state: state, task: nil)}

      {:error, %TeslaApi.Error{} = e} ->
        message =
          case e.reason do
            :captcha_does_not_match ->
              gettext("Captcha does not match")

            :recaptcha_required ->
              gettext("Recaptcha is required")

            :invalid_credentials ->
              gettext("Invalid email address and password combination")

            :token_refresh ->
              gettext("Tokens are invalid")

            :account_locked ->
              gettext(
                "Your Tesla account is locked due to too many failed sign in attempts. " <>
                  "To unlock your account, reset your password"
              )

            _ ->
              Exception.message(e)
          end

        case {socket.assigns.state, e.reason} do
          {%State.Captcha{prev_state: %State.Credentials{} = prev_state}, :captcha_does_not_match} ->
            credentials = Ecto.Changeset.apply_changes(prev_state.changeset)

            task =
              Task.async(fn ->
                # "Sign In" again to retrieve the new captcha image
                call(socket.assigns.api, :sign_in, [{credentials.email, credentials.password}])
              end)

            {:noreply, assign(socket, error: message, task: task)}

          {%State.Captcha{prev_state: %State.Credentials{} = prev_state}, _reason} ->
            {:noreply, assign(socket, state: prev_state, error: message, task: nil)}

          {_state, _reason} ->
            {:noreply, assign(socket, error: message, task: nil)}
        end
    end
  end

  defp get_api(socket) do
    case get_connect_params(socket) do
      %{api: api} -> api
      _ -> Api
    end
  end

  defp redirect_to_carlive(socket) do
    socket
    |> put_flash(:success, gettext("Signed in successfully"))
    |> redirect(to: Routes.car_path(socket, :index))
  end
end
