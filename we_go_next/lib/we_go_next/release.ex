defmodule WeGoNext.Release do
  @moduledoc """
  Release tasks for deployed nodes.
  """

  @app :we_go_next

  alias WeGoNext.Mirror.PublicReport

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

  @doc """
  Creates or updates the public report slug used by `/r/:slug`.

  Intended release usage:

      bin/we_go_next eval 'WeGoNext.Release.upsert_public_report("raid-night", "Raid Night")'
  """
  def upsert_public_report(slug, title, enabled \\ true)
      when is_binary(slug) and is_binary(title) and is_boolean(enabled) do
    Application.load(@app)

    repo_results =
      for repo <- Application.fetch_env!(@app, :ecto_repos) do
        {:ok, result, _apps} =
          Ecto.Migrator.with_repo(repo, fn repo ->
            changeset =
              PublicReport.changeset(%PublicReport{}, %{
                slug: slug,
                title: title,
                enabled: enabled
              })

            repo.insert!(
              changeset,
              on_conflict: {:replace, [:title, :enabled, :updated_at]},
              conflict_target: [:slug]
            )
          end)

        result
      end

    List.first(repo_results)
  end
end
