defmodule TeslaMateWeb.Router do
  use TeslaMateWeb, :router

  alias TeslaMate.Settings

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash

    # Query first so the settings UI language switcher (?locale=) beats the
    # stored session. The strict sources reject locales that are not close
    # to a supported one, so the chain falls through to the configured
    # default instead of best-matching an unrelated language.
    plug Localize.Plug.PutLocale,
      from: [
        {TeslaMateWeb.Plugs.Locale, :from_query},
        {TeslaMateWeb.Plugs.Locale, :from_session},
        {TeslaMateWeb.Plugs.Locale, :from_accept_language}
      ]

    plug TeslaMateWeb.Plugs.Locale

    plug :put_root_layout, {TeslaMateWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_settings
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TeslaMateWeb do
    pipe_through :browser

    get "/", CarController, :index
    get "/drive/:id/gpx", DriveController, :gpx

    live_session :default do
      live "/sign_in", SignInLive.Index
      live "/settings", SettingsLive.Index
      live "/geo-fences", GeoFenceLive.Index
      live "/geo-fences/new", GeoFenceLive.Form
      live "/geo-fences/:id/edit", GeoFenceLive.Form
      live "/charge-cost/:id", ChargeLive.Cost
      live "/import", ImportLive.Index
    end
  end

  scope "/api", TeslaMateWeb do
    pipe_through :api

    put "/car/:id/logging/resume", CarController, :resume_logging
    put "/car/:id/logging/suspend", CarController, :suspend_logging
  end

  def fetch_settings(conn, _opts) do
    settings = Settings.get_global_settings!()
    conn = assign(conn, :settings, settings)

    # An unconditional write would re-serialize the settings struct and
    # re-sign the session cookie on every response — and keep the session
    # permanently dirty, defeating the compare-then-write in
    # TeslaMateWeb.Plugs.Locale.
    if get_session(conn, :settings) == settings do
      conn
    else
      put_session(conn, :settings, settings)
    end
  end
end
