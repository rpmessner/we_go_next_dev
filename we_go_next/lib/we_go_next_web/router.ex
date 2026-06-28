defmodule WeGoNextWeb.Router do
  use WeGoNextWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {WeGoNextWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :parser_mode do
    plug(WeGoNextWeb.Plugs.RequireMode, :parser)
  end

  scope "/", WeGoNextWeb do
    pipe_through(:browser)

    live("/failures", FailureLive.Index, :index)
  end

  scope "/", WeGoNextWeb do
    pipe_through([:browser, :parser_mode])

    live("/", EncounterLive.Index, :index)
    live("/encounters/:id", EncounterLive.Show, :show)
    live("/settings", SettingsLive, :index)
  end

  scope "/api", WeGoNextWeb do
    pipe_through(:api)

    post("/ingest", IngestController, :create)
  end
end
