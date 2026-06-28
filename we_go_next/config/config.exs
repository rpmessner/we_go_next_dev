# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
import Config

# Configure the Repo
config :we_go_next,
  ecto_repos: [WeGoNext.Repo],
  mode: :parser,
  mirror_ingest_max_bytes: 1_000_000

config :we_go_next, WeGoNext.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "we_go_next_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Configures the endpoint
config :we_go_next, WeGoNextWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: WeGoNextWeb.ErrorHTML, json: WeGoNextWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: WeGoNext.PubSub,
  live_view: [signing_salt: "Xn+p7LvK"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  we_go_next: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  we_go_next: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
