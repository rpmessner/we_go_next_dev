import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# temporary application is started.

case System.get_env("MODE") do
  nil ->
    :ok

  "" ->
    :ok

  "parser" ->
    config :we_go_next, mode: :parser

  "public" ->
    config :we_go_next, mode: :public

  mode ->
    raise "MODE must be either parser or public, got: #{inspect(mode)}"
end

if database_url = System.get_env("DATABASE_URL") do
  pool_size = String.to_integer(System.get_env("POOL_SIZE") || "10")

  config :we_go_next, WeGoNext.Repo,
    url: database_url,
    pool_size: pool_size
end

if config_env() == :prod do
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
    secret_key_base: secret_key_base
end
