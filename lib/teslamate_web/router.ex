defmodule TeslaMateWeb.Router do
  use TeslaMateWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TeslaMateWeb do
    pipe_through :browser

    get "/", PageController, :index
  end

  scope "/api", TeslaMateWeb do
    pipe_through :api

    resources "/car", CarController, only: [:index, :show, :update]
    put "/car/:id/suspend", CarController, :suspend
    put "/car/:id/wake_up", CarController, :wake_up
  end
end
