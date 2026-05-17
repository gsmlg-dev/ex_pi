defmodule ExPiWeb.Router do
  use ExPiWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ExPiWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", ExPiWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/sessions/:id", SessionLive, :show
  end
end
