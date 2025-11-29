import Config

# For development, we disable any cache and enable
# debugging and code reloading.

config :we_go_next, WeGoNextWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "J9kK8vQn2XpZa3L5mT7rY1wB6dF4hN0sC2eG9iO3xU5jV8nM1qW4aS7zR0tP6yHx",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:we_go_next, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:we_go_next, ~w(--watch)]}
  ]

# Watch static and templates for browser reloading.
config :we_go_next, WeGoNextWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/we_go_next_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Enable dev routes for dashboard and mailbox
config :we_go_next, dev_routes: true

# Set a higher stacktrace during development
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Include HEEx debug annotations as HTML comments in rendered markup
config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true
