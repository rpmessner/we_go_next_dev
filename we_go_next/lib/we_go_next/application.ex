defmodule WeGoNext.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WeGoNext.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc false
  def children(mode \\ WeGoNext.mode()) do
    [
      # Start the Repo
      WeGoNext.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: WeGoNext.PubSub}
    ] ++
      parser_children(mode) ++
      [
        # Start the Endpoint (http/https)
        WeGoNextWeb.Endpoint
      ]
  end

  defp parser_children(:parser) do
    [
      # Task supervisor for background imports
      {Task.Supervisor, name: WeGoNext.ImportTaskSupervisor},
      # Import worker (manages imports per user, survives page refresh)
      WeGoNext.ImportWorker,
      # Start the file watcher (tracks current combat log file)
      WeGoNext.FileWatcher
    ]
  end

  defp parser_children(:public), do: []

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WeGoNextWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
