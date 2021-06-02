defmodule TeslaMateWeb.SignInLive.Index do
  use TeslaMateWeb, :live_view

  import Core.Dependency, only: [call: 2, call: 3]
  alias TeslaMate.{Auth, Api}

  defp initial_state, do: {:credentials, credentials_changeset()}

  @impl true
  def mount(_params, %{"locale" => locale}, socket) do
    if connected?(socket), do: Gettext.put_locale(locale)

    assigns = %{
      api: get_api(socket),
      page_title: gettext("Sign in"),
      captcha: nil,
      callback: fn _, _, _ -> :error end,
      error: nil,
      task: nil,
      state: initial_state()
    }

    send(self(), :prepare_sign_in)

    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      case params["use_api_tokens"] do
        "true" -> assign(socket, state: {:tokens, Auth.change_tokens()})
        "false" -> assign(socket, state: initial_state())
        _ -> socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"credentials" => c}, %{assigns: %{state: {:credentials, _}}} = s) do
    changeset =
      c
      |> credentials_changeset()
      |> Map.put(:action, :update)

    {:noreply, assign(s, state: {:credentials, changeset}, error: nil)}
  end

  def handle_event("validate", %{"tokens" => c}, %{assigns: %{state: {:tokens, _}}} = s) do
    changeset =
      c
      |> Auth.change_tokens()
      |> Map.put(:action, :update)

    {:noreply, assign(s, state: {:tokens, changeset}, error: nil)}
  end

  def handle_event("validate", %{"mfa" => mfa}, %{assigns: %{state: {:mfa, data}}} = socket) do
    {_changeset, devices, callback} = data

    changeset =
      mfa
      |> mfa_changeset()
      |> Map.put(:action, :update)

    task =
      if changeset.valid? do
        %{passcode: passcode, device_id: device_id} = Ecto.Changeset.apply_changes(changeset)

        Task.async(fn ->
          callback.(device_id, passcode)
        end)
      end

    state = {:mfa, {changeset, devices, callback}}

    {:noreply, assign(socket, state: state, task: task, error: nil)}
  end

  def handle_event("sign_in", _, %{assigns: %{state: {:credentials, changeset}}} = socket) do
    credentials = Ecto.Changeset.apply_changes(changeset)

    task =
      Task.async(fn ->
        case socket.assigns.captcha do
          nil ->
            socket.assigns.callback.(credentials.email, credentials.password)

          _ ->
            socket.assigns.callback.(credentials.email, credentials.password, credentials.captcha)
        end
      end)

    {:noreply, assign(socket, task: task)}
  end

  def handle_event("sign_in", _, %{assigns: %{state: {:tokens, changeset}}} = socket) do
    tokens = Ecto.Changeset.apply_changes(changeset)

    task =
      Task.async(fn ->
        call(socket.assigns.api, :sign_in, [tokens])
      end)

    {:noreply, assign(socket, task: task)}
  end

  def handle_event("use_api_tokens", _params, socket) do
    path = Routes.live_path(socket, __MODULE__, %{use_api_tokens: true})
    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("use_credentials", _params, socket) do
    path = Routes.live_path(socket, __MODULE__, %{use_api_tokens: false})
    {:noreply, push_patch(socket, to: path)}
  end

  @impl true
  def handle_info(:prepare_sign_in, socket) do
    case call(socket.assigns.api, :prepare_sign_in) do
      {:ok, {:captcha, captcha, callback}} ->
        {:noreply, assign(socket, captcha: captcha, callback: callback, task: nil)}

      {:ok, callback} ->
        {:noreply, assign(socket, captcha: nil, callback: callback, task: nil)}

      {:error, %TeslaApi.Error{} = e} ->
        {:noreply, assign(socket, error: Exception.message(e), task: nil)}
    end
  end

  def handle_info({ref, result}, %{assigns: %{task: %Task{ref: ref}}} = socket) do
    Process.demonitor(ref, [:flush])

    case result do
      :ok ->
        Process.sleep(250)
        {:noreply, redirect_to_carlive(socket)}

      {:ok, {:mfa, devices, callback}} ->
        devices = Enum.map(devices, fn %{"name" => name, "id" => id} -> {name, id} end)
        state = {:mfa, {mfa_changeset(), devices, callback}}
        {:noreply, assign(socket, state: state, task: nil)}

      {:error, %TeslaApi.Error{} = e} ->
        message =
          case e.reason do
            :captcha_does_not_match ->
              gettext("Captcha does not match")

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

        captcha =
          cond do
            e.reason in [:captcha_does_not_match, :invalid_credentials] ->
              send(self(), :prepare_sign_in)
              nil

            :else ->
              socket.assigns.captcha
          end

        {:noreply, assign(socket, captcha: captcha, error: message, task: nil)}
    end
  end

  defp credentials_changeset(attrs \\ %{}) do
    import Ecto.Changeset

    {%{}, %{email: :string, password: :string, captcha: :string}}
    |> cast(attrs, [:email, :password, :captcha])
    |> validate_required([:email, :password])
  end

  defp mfa_changeset(attrs \\ %{}) do
    import Ecto.Changeset

    {%{}, %{passcode: :string, device_id: :string}}
    |> cast(attrs, [:passcode, :device_id])
    |> validate_required([:passcode, :device_id])
    |> validate_length(:passcode, is: 6)
    |> validate_format(:passcode, ~r/\d{6}/)
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
