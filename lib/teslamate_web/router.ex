defmodule TeslaMateWeb.Router do
  use TeslaMateWeb, :router

  alias TeslaMate.Api

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug Phoenix.LiveView.Flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :sign_in do
    defp redirect_unless_signed_in(conn, _opts) do
      case Api.signed_in?() do
        false -> conn |> redirect(to: "/sign_in") |> halt()
        true -> conn
      end
    end

    plug :redirect_unless_signed_in
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TeslaMateWeb do
    pipe_through :browser
    pipe_through :sign_in

    live "/", CarLive.Index
  end

  scope "/sign_in", TeslaMateWeb do
    pipe_through :browser

    live "/", SignInLive.Index
  end

  scope "/api", TeslaMateWeb do
    pipe_through :api

    resources "/car", CarController, only: [:index, :show, :update]
    put "/car/:id/logging/resume", CarController, :resume_logging
    put "/car/:id/logging/suspend", CarController, :suspend_logging

    resources "/addresses", AddressController
  end
end
