defmodule TeslaMateWeb.InitAssigns do
  @moduledoc """
  Ensures common `assigns` are applied to all LiveViews attaching this hook.
  """

  import Phoenix.Component
  import Phoenix.LiveView, only: [connected?: 1]

  alias TeslaMate.Settings
  alias TeslaMate.Settings.GlobalSettings

  @session_key TeslaMateWeb.Plugs.Locale.session_key()
  @gettext_locales TeslaMateWeb.Plugs.Locale.gettext_locales()

  def on_mount(:locale, _params, session, socket) do
    # Membership keeps this path consistent with the dead render and
    # rejects legacy session values the pre-localize PutSession plug
    # wrote verbatim (nil, or a locale a later release removed) —
    # Gettext.put_locale/2 raises on nil.
    case session do
      %{@session_key => locale} when locale in @gettext_locales ->
        Gettext.put_locale(TeslaMateWeb.Gettext, locale)

      _other ->
        :ok
    end

    {:cont, assign(socket, :locale, Gettext.get_locale(TeslaMateWeb.Gettext))}
  end

  @doc """
  The global settings to mount a LiveView with.

  The session holds the settings `fetch_settings` read for the HTTP request,
  current for the dead render. A connected mount gets the session of the
  websocket's connect instead, which a later live navigation reuses even
  though settings changed over the websocket since; so it reads them anew.
  """
  def global_settings(%GlobalSettings{} = session_settings, socket) do
    if connected?(socket), do: Settings.get_global_settings!(), else: session_settings
  end
end
