defmodule WeGoNext.Analysis.Tools.PullSummary do
  @moduledoc "Stored encounter-document overview, roster and pull signals."
  @behaviour WeGoNext.Analysis.Tool
  alias WeGoNext.Analysis.{PullScope, Result}
  alias WeGoNext.{Documents, Repo}
  alias WeGoNext.Gold.DimEncounter

  def name, do: "pull_summary"

  def description,
    do:
      "Read a pull's stored encounter-document overview, roster and pull signals. Pull is a gold pull id in this session log. Data rows have section and value; roster has one row per player. Does not rebuild missing or stale documents. Missed-kick signals use overbroad interrupt silver: verify with log_events. Follow next_cursor with identical arguments."

  def input_schema, do: PullScope.schema("pull")

  def run(args, session) do
    with {:ok, [pull]} <- PullScope.fetch([args["pull"]], session),
         %DimEncounter{source_encounter_key: key} when is_binary(key) <-
           Repo.get(DimEncounter, pull.pull_id),
         {:ok, document} <- Documents.fetch_encounter(key) do
      rows =
        [{"overview", overview(document)}, {"pull_signals", signals(document)}] ++
          Enum.map(document.roster, &{"roster", Map.delete(&1, :operator)})

      rows =
        Enum.map(rows, fn {section, value} ->
          {%{section: section, value: value}, PullScope.evidence(pull, "encounter_document")}
        end)

      Result.page(rows, args, {name(), session.id})
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      _ -> {:error, "Encounter document unavailable; generate it before using pull_summary"}
    end
  end

  defp overview(document) do
    %{
      encounter: Map.delete(document.encounter, :operator),
      counts: document.counts,
      schema_version: document.schema_version,
      generated_at: document.generated_at,
      derivation_version: document.derivation_version,
      source_encounter_key: document.source_encounter_key
    }
  end

  defp signals(document) do
    spells = document.interrupt_coverage.spell_coverage
    debuffs = document.pull_review.debuffs.boss

    %{
      deaths: document.counts.deaths,
      tracked_failures: document.failure_preview.counts,
      missed_kicks: Enum.sum(Enum.map(spells, & &1.missed_casts)),
      interrupt_caveat:
        "Interrupt silver overcounts opportunities and misses; verify with log_events.",
      low_damage_players: length(document.pull_review.low_dps),
      top_damage_taken: document.pull_review.damage_taken_spells |> List.first(),
      encounter_debuffs: length(debuffs),
      debuff_applications: Enum.sum(Enum.map(debuffs, & &1.applications)),
      roster: document.counts.players
    }
  end
end
