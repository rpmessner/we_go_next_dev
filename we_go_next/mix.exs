defmodule WeGoNext.MixProject do
  use Mix.Project

  def project do
    [
      app: :we_go_next,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      releases: releases(),
      test_pattern: "*_test.exs",
      test_paths: ["test"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {WeGoNext.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind we_go_next", "esbuild we_go_next"],
      "assets.deploy": [
        "tailwind we_go_next --minify",
        "esbuild we_go_next --minify",
        "phx.digest"
      ],
      quality: [
        "format --check-formatted",
        "zig.get",
        "cmd sh -c 'for i in $(seq 1 30); do if find \"$HOME/.cache/zigler\" -maxdepth 3 -type f -name zig -perm /111 | grep -q .; then exit 0; fi; sleep 1; done; echo \"zig executable not found\"; exit 1'",
        "compile --warnings-as-errors",
        "credo --only warning",
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "test"
      ],
      test: ["test"]
    ]
  end

  # Ensure test always runs in test env, even if MIX_ENV is set in shell
  def cli do
    [preferred_envs: [quality: :test, test: :test]]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:floki, "~> 0.36"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.0"},
      {:ecto_sql, "~> 3.10"},
      {:phoenix_ecto, "~> 4.4"},
      {:postgrex, "~> 0.17"},
      {:req, "~> 0.5"},
      {:wallaby, "~> 0.30", runtime: false, only: :test},
      {:tidewave, "~> 0.6", only: :dev},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:zigler, "~> 0.15.1", runtime: false}
    ]
  end

  defp releases do
    [
      we_go_next: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent]
      ]
    ]
  end
end
