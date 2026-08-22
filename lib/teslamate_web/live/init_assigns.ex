defmodule TeslaMateWeb.InitAssigns do
  @moduledoc """
  Ensures common `assigns` are applied to all LiveViews attaching this hook.
  """

  import Phoenix.Component

  @session_key TeslaMateWeb.Plugs.Locale.session_key()

  def on_mount(:locale, _params, session, socket) do
    # is_binary: the pre-localize PutSession plug wrote the CLDR tag's
    # gettext_locale_name verbatim, which could be nil — and
    # Gettext.put_locale/2 raises on nil.
    case session do
      %{@session_key => locale} when is_binary(locale) ->
        Gettext.put_locale(TeslaMateWeb.Gettext, locale)

      _other ->
        :ok
    end

    {:cont, assign(socket, :locale, Gettext.get_locale(TeslaMateWeb.Gettext))}
  end
end
