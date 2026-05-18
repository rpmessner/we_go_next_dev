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

  scope "/", WeGoNextWeb do
    pipe_through(:browser)

    live("/", EncounterLive.Index, :index)
    live("/failures", FailureLive.Index, :index)
    live("/settings", SettingsLive, :index)
  end
end
