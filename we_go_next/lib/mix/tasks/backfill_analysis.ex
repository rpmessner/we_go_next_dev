defmodule Mix.Tasks.WeGoNext.BackfillAnalysis do
  @moduledoc """
  Backfills analysis for encounters that have raw_log but no cached analysis.

  Usage:
    mix we_go_next.backfill_analysis
  """
  use Mix.Task

  alias WeGoNext.Repo
  alias WeGoNext.Encounters.Encounter, as: EncounterRecord
  alias WeGoNext.Analyzers.AnalysisCache
  import Ecto.Query

  @shortdoc "Backfill analysis for existing encounters"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    # Find encounters with raw_log but empty/null analysis
    encounters =
      EncounterRecord
      |> where([e], not is_nil(e.raw_log) and e.raw_log != "")
      |> where([e], is_nil(e.analysis) or e.analysis == ^%{})
      |> Repo.all()

    total = length(encounters)

    if total == 0 do
      Mix.shell().info("No encounters need analysis backfill.")
    else
      Mix.shell().info("Backfilling analysis for #{total} encounter(s)...")

      encounters
      |> Enum.with_index(1)
      |> Enum.each(fn {record, index} ->
        Mix.shell().info("[#{index}/#{total}] Processing: #{record.name}...")

        {time_us, _} = :timer.tc(fn ->
          backfill_encounter(record)
        end)

        Mix.shell().info("  Done in #{Float.round(time_us / 1000, 1)}ms")
      end)

      Mix.shell().info("\nBackfill complete!")
    end
  end

  defp backfill_encounter(%EncounterRecord{} = record) do
    # Parse raw_log to get encounter struct with events
    encounter = EncounterRecord.to_encounter_struct(record)

    # Compute analysis
    analysis = AnalysisCache.compute(encounter)

    # Update the record
    record
    |> Ecto.Changeset.change(%{analysis: analysis})
    |> Repo.update!()
  end
end
