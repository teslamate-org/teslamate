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

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_v1 do
    plug :accepts, ["json"]
    plug TeslaMateWeb.Api.EnableApiPlug
  end

  pipeline :api_auth do
    plug TeslaMateWeb.Api.Auth.Plug
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

  scope "/api/v1", TeslaMateWeb.Api do
    pipe_through :api_v1

    post "/auth/login", Auth.AuthController, :login
    get "/health", HealthController, :index

    scope "/" do
      pipe_through :api_auth

      get "/cars", CarController, :index
      get "/cars/:id", CarController, :show
      get "/cars/:car_id/summary", CarController, :summary
      get "/cars/:car_id/drives", DriveController, :index
      get "/cars/:car_id/charges", ChargeController, :index
      get "/cars/:car_id/positions", PositionController, :index

      get "/drives/:id", DriveController, :show
      get "/drives/:id/gpx", DriveController, :gpx
      get "/charges/:id", ChargeController, :show
    end
  end

  def fetch_settings(conn, _opts) do
    settings = Settings.get_global_settings!()

    conn
    |> assign(:settings, settings)
    |> put_session(:settings, settings)
  end
end
