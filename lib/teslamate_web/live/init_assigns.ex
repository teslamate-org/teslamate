defmodule TeslaMateWeb.InitAssigns do
  @moduledoc """
  Ensures common `assigns` are applied to all LiveViews attaching this hook.
  """

  import Phoenix.Component

  def on_mount(:locale, _params, %{"gettext_locale" => locale}, socket) do
    Gettext.put_locale(locale)
    {:cont, assign(socket, :locale, locale)}
  end
end
