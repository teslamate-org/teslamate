defmodule TeslaMateWeb.Router do
  use TeslaMateWeb, :router

  alias TeslaMateWeb.Plugs.{SetLocale, Donate}
  alias TeslaMate.Settings

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug SetLocale
    plug :put_root_layout, {TeslaMateWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug Donate
    plug :fetch_settings
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TeslaMateWeb do
    pipe_through :browser

    get "/", CarController, :index
    live "/sign_in", SignInLive.Index
    live "/settings", SettingsLive.Index
    live "/geo-fences", GeoFenceLive.Index
    live "/geo-fences/new", GeoFenceLive.Form
    live "/geo-fences/:id/edit", GeoFenceLive.Form
    live "/charge-cost/:id", ChargeLive.Cost
    live "/import", ImportLive.Index
    get "/drive/:id/gpx", DriveController, :gpx
    get "/donate", DonateController, :index
  end

  scope "/api", TeslaMateWeb do
    pipe_through :api

    put "/car/:id/logging/resume", CarController, :resume_logging
    put "/car/:id/logging/suspend", CarController, :suspend_logging
  end

  defp fetch_settings(conn, _opts) do
    settings = Settings.get_global_settings!()

    conn
    |> assign(:settings, settings)
    |> put_session(:settings, settings)
  end
end
