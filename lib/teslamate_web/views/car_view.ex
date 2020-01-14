defmodule TeslaMateWeb.CarView do
  use TeslaMateWeb, :view

  alias TeslaMate.{Locations, Convert}

  def render("command_failed.json", %{reason: reason}) do
    %{error: reason}
  end
end
