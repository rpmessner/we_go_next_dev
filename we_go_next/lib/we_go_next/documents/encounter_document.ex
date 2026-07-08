defmodule WeGoNext.Documents.EncounterDocument do
  @moduledoc """
  Encodes the versioned encounter-detail JSON document.
  """

  alias WeGoNext.Gold.FactFailure.Derivation
  alias WeGoNext.Gold.{DimEncounter, EncounterDetail, ObservedMechanics}

  @schema_version 1

  @doc """
  Encodes one encounter's current detail read models into the WE-25 contract.
  """
  @spec encode(pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def encode(encounter_dim_id, opts \\ []) when is_integer(encounter_dim_id) do
    with {:ok, detail} <- EncounterDetail.get(encounter_dim_id),
         {:ok, source_encounter_key} <- fetch_source_encounter_key(detail.encounter),
         {:ok, observed_mechanics} <- ObservedMechanics.for_encounter(detail.encounter.id) do
      {:ok,
       normalize(%{
         schema_version: @schema_version,
         generated_at: Keyword.get(opts, :generated_at, DateTime.utc_now()),
         derivation_version: Derivation.current_version(),
         source_encounter_key: source_encounter_key,
         encounter: encode_encounter(detail.encounter),
         counts: encode_counts(detail.counts),
         roster: Enum.map(detail.roster, &encode_roster_player/1),
         deaths: Enum.map(detail.deaths, &encode_death/1),
         pull_review: encode_pull_review(detail.pull_review),
         failure_preview: encode_failure_preview(detail.failure_preview),
         interrupt_coverage: encode_interrupt_coverage(detail.interrupt_coverage),
         personal_pull_summary: encode_personal_pull_summary(detail.personal_pull_summary),
         observed_mechanics: encode_observed_mechanics(observed_mechanics)
       })}
    end
  end

  def schema_version, do: @schema_version

  defp fetch_source_encounter_key(%DimEncounter{id: id, source_encounter_key: nil}) do
    {:error, {:missing_source_encounter_key, id}}
  end

  defp fetch_source_encounter_key(%DimEncounter{source_encounter_key: key}) when is_binary(key),
    do: {:ok, key}

  defp encode_encounter(%DimEncounter{} = encounter) do
    %{
      id: encounter.id,
      source_encounter_key: encounter.source_encounter_key,
      wow_encounter_id: encounter.wow_encounter_id,
      name: encounter.name,
      difficulty_id: encounter.difficulty_id,
      difficulty_name: encounter.difficulty_name,
      group_size: encounter.group_size,
      instance_id: encounter.instance_id,
      start_time: encounter.start_time,
      end_time: encounter.end_time,
      success: encounter.success,
      fight_time_ms: encounter.fight_time_ms,
      operator: %{
        inserted_at: encounter.inserted_at,
        updated_at: encounter.updated_at
      }
    }
  end

  defp encode_counts(counts) do
    %{
      deaths: Map.get(counts, :deaths, 0),
      interrupt_opportunities: Map.get(counts, :interrupt_opportunities, 0),
      players: Map.get(counts, :players, 0),
      operator: %{
        damage_taken_groups: Map.get(counts, :damage_taken_groups, 0),
        damage_taken_events: Map.get(counts, :damage_taken_events, 0),
        damage_done_groups: Map.get(counts, :damage_done_groups, 0),
        debuff_applications: Map.get(counts, :debuff_applications, 0),
        defensive_buff_windows: Map.get(counts, :defensive_buff_windows, 0),
        failure_facts: Map.get(counts, :failure_facts, 0)
      }
    }
  end

  defp encode_roster_player(player) do
    %{
      player_guid: player.player_guid,
      player_name: player.player_name,
      class_id: player.class_id,
      spec_id: player.spec_id,
      item_level: player.item_level,
      detected_role: player.detected_role,
      operator: %{
        id: Map.get(player, :id),
        encounter_dim_id: Map.get(player, :encounter_dim_id),
        inserted_at: Map.get(player, :inserted_at)
      }
    }
  end

  defp encode_death(death) do
    death
    |> Map.drop([:id])
    |> Map.put(:operator, %{id: Map.get(death, :id)})
  end

  defp encode_pull_review(pull_review) do
    %{
      damage_done: Map.get(pull_review, :damage_done, []),
      low_dps: Map.get(pull_review, :low_dps, []),
      damage_taken_spells: Map.get(pull_review, :damage_taken_spells, []),
      debuffs: Map.get(pull_review, :debuffs, %{all: [], boss: [], player: []})
    }
  end

  defp encode_failure_preview(preview) do
    %{
      counts: Map.get(preview, :counts, %{}),
      mechanics: preview |> Map.get(:mechanics, []) |> Enum.map(&encode_failure_mechanic/1),
      operator: %{
        diagnostics: Map.get(preview, :diagnostics, [])
      }
    }
  end

  defp encode_failure_mechanic(mechanic) do
    mechanic
    |> Map.drop([:criterion_dim_id, :players, :targeted_cone_events])
    |> Map.put(:players, mechanic |> Map.get(:players, []) |> Enum.map(&encode_failure_player/1))
    |> put_optional(
      :targeted_cone_events,
      mechanic |> Map.get(:targeted_cone_events, []) |> Enum.map(&encode_targeted_cone_event/1)
    )
    |> Map.put(:operator, %{criterion_dim_id: Map.get(mechanic, :criterion_dim_id)})
  end

  defp encode_failure_player(player) do
    player
    |> Map.drop([:player_dim_id])
    |> Map.put(:operator, %{player_dim_id: Map.get(player, :player_dim_id)})
  end

  defp encode_targeted_cone_event(event) do
    event
    |> Map.drop([:criterion_dim_id])
    |> Map.put(:operator, %{criterion_dim_id: Map.get(event, :criterion_dim_id)})
  end

  defp encode_interrupt_coverage(coverage) do
    %{
      spell_coverage:
        coverage
        |> Map.get(:spell_coverage, [])
        |> Enum.map(fn spell ->
          spell
          |> Map.drop([:criterion_dim_ids])
          |> Map.put(:operator, %{criterion_dim_ids: Map.get(spell, :criterion_dim_ids)})
        end),
      player_contributions: Map.get(coverage, :player_contributions, [])
    }
  end

  defp encode_personal_pull_summary(summary) do
    %{
      selected_player_guid: nil,
      players: summary |> Map.get(:players, []) |> Enum.map(&encode_personal_player/1),
      operator: %{
        selected_player_guid: Map.get(summary, :selected_player_guid)
      }
    }
  end

  defp encode_personal_player(player) do
    player
    |> Map.update(:performance, %{pulls: [], summary: %{}}, &encode_performance/1)
    |> Map.update(:defensive_analysis, %{windows: [], events: [], summary: %{}}, & &1)
  end

  defp encode_performance(performance) do
    %{
      summary: Map.get(performance, :summary, %{}),
      pulls: performance |> Map.get(:pulls, []) |> Enum.map(&encode_performance_pull/1)
    }
  end

  defp encode_performance_pull(pull) do
    pull
    |> Map.drop([:encounter_dim_id])
    |> Map.put(:operator, %{encounter_dim_id: Map.get(pull, :encounter_dim_id)})
  end

  defp encode_observed_mechanics(observed_mechanics) do
    %{
      counts: encode_observed_counts(observed_mechanics.counts),
      mechanics: Enum.map(observed_mechanics.mechanics, &encode_observed_mechanic/1)
    }
  end

  defp encode_observed_counts(counts) do
    %{
      observed_spells: Map.get(counts, :observed_spells, 0),
      operator: Map.drop(counts, [:observed_spells])
    }
  end

  defp encode_observed_mechanic(mechanic) do
    %{
      spell_id: mechanic.spell_id,
      spell_name: mechanic.spell_name,
      boss_name: mechanic.boss_name,
      observed: mechanic.observed,
      facts: mechanic.facts,
      operator: %{
        catalog: mechanic.catalog,
        criteria: mechanic.criteria,
        rule_status: mechanic.rule_status,
        diagnostics: mechanic.diagnostics
      }
    }
  end

  defp put_optional(map, _key, []), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp normalize(%DateTime{} = value), do: value
  defp normalize(%NaiveDateTime{} = value), do: value
  defp normalize(%Date{} = value), do: value
  defp normalize(%Time{} = value), do: value
  defp normalize(%Decimal{} = value), do: Decimal.to_string(value)

  defp normalize(%_{} = value) do
    value
    |> Map.from_struct()
    |> Map.drop([:__meta__, :encounter])
    |> normalize()
  end

  defp normalize(value) when is_map(value) do
    Map.new(value, fn {key, value} -> {key, normalize(value)} end)
  end

  defp normalize(value) when is_list(value), do: Enum.map(value, &normalize/1)

  defp normalize(value) when is_atom(value) and not is_boolean(value) and not is_nil(value),
    do: Atom.to_string(value)

  defp normalize(value), do: value
end
