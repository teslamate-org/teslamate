defmodule TeslaMateWeb.Router do
  use TeslaMateWeb, :router

  alias TeslaMate.Settings

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash

    plug Cldr.Plug.AcceptLanguage,
      cldr_backend: TeslaMateWeb.Cldr,
      no_match_log_level: :debug

    plug Cldr.Plug.PutLocale,
      apps: [:cldr, :gettext],
      from: [:query, :session, :accept_language],
      gettext: TeslaMateWeb.Gettext,
      cldr: TeslaMateWeb.Cldr

    plug TeslaMateWeb.Plugs.PutSession

    plug :put_root_layout, {TeslaMateWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_settings
  end

  pipeline :web_auth do
    plug TeslaMateWeb.Plugs.WebAuth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TeslaMateWeb do
    pipe_through [:browser, :web_auth]

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

  # Web认证页面，不需要认证
  scope "/", TeslaMateWeb do
    pipe_through :browser

    live_session :web_auth do
      live "/web_auth", WebAuthLive.Index
    end

    # 认证相关路由
    post "/auth/authenticate", AuthController, :authenticate
    delete "/auth/logout", AuthController, :logout
  end

  scope "/api", TeslaMateWeb do
    pipe_through :api

    put "/car/:id/logging/resume", CarController, :resume_logging
    put "/car/:id/logging/suspend", CarController, :suspend_logging
  end

  def fetch_settings(conn, _opts) do
    settings = Settings.get_global_settings!()

    conn
    |> assign(:settings, settings)
    |> put_session(:settings, settings)
  end
end
