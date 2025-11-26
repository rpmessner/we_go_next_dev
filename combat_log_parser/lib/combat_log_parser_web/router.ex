defmodule CombatLogParserWeb.Router do
  use CombatLogParserWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CombatLogParserWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", CombatLogParserWeb do
    pipe_through :browser

    live "/", EncounterLive.Index, :index
    live "/encounters/:id", EncounterLive.Show, :show
  end
end
