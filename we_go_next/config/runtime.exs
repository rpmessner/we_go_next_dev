import Config

config :we_go_next,
  public_base_url: System.get_env("PUBLIC_BASE_URL") || "https://we-go-next.gigalixirapp.com",
  public_report_slug: System.get_env("PUBLIC_REPORT_SLUG") || "raid-night"

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
    pool_size: pool_size,
    ssl: true
end

if documents_root = System.get_env("DOCUMENTS_ROOT") do
  config :we_go_next, documents_root: documents_root
end

case System.get_env("DOCUMENTS_STORE") do
  nil ->
    :ok

  "" ->
    :ok

  "filesystem" ->
    config :we_go_next, documents_store: WeGoNext.Documents.Store.FileSystem

  "r2" ->
    config :we_go_next, documents_store: WeGoNext.Documents.Store.R2

  store ->
    raise "DOCUMENTS_STORE must be either filesystem or r2, got: #{inspect(store)}"
end

if r2_endpoint = System.get_env("R2_ENDPOINT") do
  config :we_go_next,
    documents_r2: %{
      endpoint: r2_endpoint,
      bucket: System.fetch_env!("R2_BUCKET"),
      access_key_id: System.fetch_env!("R2_ACCESS_KEY_ID"),
      secret_access_key: System.fetch_env!("R2_SECRET_ACCESS_KEY")
    }
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
