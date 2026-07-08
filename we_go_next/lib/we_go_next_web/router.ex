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

  pipeline :public_viewer do
    plug(WeGoNextWeb.Plugs.PublicViewer)
  end

  scope "/", WeGoNextWeb do
    pipe_through(:browser)

    live("/failures", FailureLive.Index, :index)
  end

  scope "/", WeGoNextWeb do
    pipe_through([:browser, :parser_mode])

    live("/", EncounterLive.Index, :index)
    live("/encounters/:source_encounter_key", EncounterLive.Show, :show)
    live("/settings", SettingsLive, :index)
  end

  scope "/api", WeGoNextWeb do
    pipe_through(:api)

    post("/reports/:slug/ingest", IngestController, :create)
  end

  scope "/r/:slug", WeGoNextWeb do
    pipe_through([:browser, :public_viewer])

    live("/", PublicLive.Encounters, :index)
    live("/failures", PublicLive.Failures, :index)
    live("/encounters/:source_encounter_key", PublicLive.EncounterFailures, :show)
  end
end
