defmodule WeGoNext.Release do
  @moduledoc """
  Release tasks for deployed nodes.
  """

  @app :we_go_next

  @doc """
  Runs all pending Ecto migrations for release deployments.
  """
  def migrate do
    Application.load(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _fun_return, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end
end
