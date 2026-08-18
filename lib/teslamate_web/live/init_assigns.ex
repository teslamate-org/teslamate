defmodule TeslaMateWeb.InitAssigns do
  @moduledoc """
  Ensures common `assigns` are applied to all LiveViews attaching this hook.
  """

  import Phoenix.Component

  def on_mount(:locale, _params, session, socket) do
    case Localize.Plug.put_locale_from_session(session, gettext: TeslaMateWeb.Gettext) do
      {:ok, _locale} ->
        :ok

      {:error, _reason} ->
        Gettext.put_locale(TeslaMateWeb.Gettext, "en")
    end

    {:cont, assign(socket, :locale, Gettext.get_locale(TeslaMateWeb.Gettext))}
  end
end
