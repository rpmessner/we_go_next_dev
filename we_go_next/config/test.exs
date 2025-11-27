import Config

# We run a server during Wallaby tests
config :we_go_next, WeGoNextWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_that_is_at_least_64_bytes_long_for_testing_purposes_only",
  server: true

# Configure Wallaby
config :wallaby,
  driver: Wallaby.Chrome,
  chromedriver: [
    headless: true
  ],
  screenshot_dir: "tmp/wallaby_screenshots",
  screenshot_on_failure: true

# Use test database
config :we_go_next, WeGoNext.Repo,
  database: "we_go_next_test",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
