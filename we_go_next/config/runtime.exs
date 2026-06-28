import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# temporary application is started.

configured_mode = System.get_env("WE_GO_NEXT_MODE") || System.get_env("MODE")

case configured_mode do
  nil ->
    :ok

  "" ->
    :ok

  "parser" ->
    config :we_go_next, mode: :parser

  "public" ->
    config :we_go_next, mode: :public

  mode ->
    raise "WE_GO_NEXT_MODE/MODE must be either parser or public, got: #{inspect(mode)}"
end

if database_url = System.get_env("DATABASE_URL") do
  pool_size = String.to_integer(System.get_env("POOL_SIZE") || "10")

  config :we_go_next, WeGoNext.Repo,
    url: database_url,
    pool_size: pool_size
end

if ingest_token = System.get_env("INGEST_TOKEN") do
  config :we_go_next, mirror_ingest_token: ingest_token
end

if viewer_slug = System.get_env("VIEWER_SLUG") do
  config :we_go_next, public_viewer_slug: viewer_slug
end

if config_env() == :prod do
  run_migrations_on_boot? =
    System.get_env("RUN_MIGRATIONS_ON_BOOT", "true") in ["1", "true", "TRUE"]

  config :we_go_next, run_migrations_on_boot: run_migrations_on_boot?

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :we_go_next, WeGoNextWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    server: true,
    secret_key_base: secret_key_base
end
