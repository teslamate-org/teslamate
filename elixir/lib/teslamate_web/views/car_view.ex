defmodule TeslaMateWeb.CarView do
  use TeslaMateWeb, :view

  def render("command_failed.json", %{reason: reason}) do
    %{error: reason}
  end
end
