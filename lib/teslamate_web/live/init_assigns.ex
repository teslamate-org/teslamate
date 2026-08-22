defmodule TeslaMateWeb.InitAssigns do
  @moduledoc """
  Ensures common `assigns` are applied to all LiveViews attaching this hook.
  """

  import Phoenix.Component

  def on_mount(:locale, _params, session, socket) do
    case session do
      %{"gettext_locale" => locale} -> Gettext.put_locale(TeslaMateWeb.Gettext, locale)
      _other -> :ok
    end

    {:cont, assign(socket, :locale, Gettext.get_locale(TeslaMateWeb.Gettext))}
  end
end
