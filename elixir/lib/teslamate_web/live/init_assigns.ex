defmodule TeslaMateWeb.InitAssigns do
  @moduledoc """
  Ensures common `assigns` are applied to all LiveViews attaching this hook.
  """

  import Phoenix.Component

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
end
