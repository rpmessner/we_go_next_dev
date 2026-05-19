defmodule WeGoNext.Gold.EncounterDetail do
  @moduledoc """
  Medallion encounter detail read model keyed by `gold.dim_encounter.id`.

  This module must not call legacy analyzers, analyzer JSON cache output, or
  `public.mechanic_criteria`.
  """

  import Ecto.Query

  alias WeGoNext.GameData.Spells
  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, FactFailure}
  alias WeGoNext.Repo

  alias WeGoNext.Silver.{
    DamageDone,
    DamageTaken,
    DamageTakenEvent,
    Death,
    DebuffApplication,
    InterruptOpportunity,
    PlayerInfo
  }

  @type t :: %{
          encounter: DimEncounter.t(),
          counts: %{atom() => non_neg_integer()},
          roster: [PlayerInfo.t()],
          deaths: [map()],
          interrupt_coverage: %{
            spell_coverage: [map()],
            player_contributions: [map()]
          },
          personal_pull_summary: %{
            selected_player_guid: String.t() | nil,
            players: [map()]
          }
        }

  @doc """
  Returns a compact encounter detail shell read model for a gold encounter ID.
  """
  @spec get(pos_integer() | String.t()) :: {:ok, t()} | {:error, :not_found | :invalid_id}
  def get(id, opts \\ []) do
    with {:ok, id} <- parse_id(id),
         %DimEncounter{} = encounter <- Repo.get(DimEncounter, id) do
      roster = roster(id)

      {:ok,
       %{
         encounter: encounter,
         counts: counts(id),
         roster: roster,
         deaths: deaths(id),
         interrupt_coverage: interrupt_coverage(id),
         personal_pull_summary:
           personal_pull_summary(id, roster, Keyword.get(opts, :character_name))
       }}
    else
      nil -> {:error, :not_found}
      :error -> {:error, :invalid_id}
    end
  end

  defp counts(encounter_dim_id) do
    %{
      damage_taken_groups: count(DamageTaken, encounter_dim_id),
      damage_taken_events: count(DamageTakenEvent, encounter_dim_id),
      damage_done_groups: count(DamageDone, encounter_dim_id),
      deaths: count(Death, encounter_dim_id),
      interrupt_opportunities: count(InterruptOpportunity, encounter_dim_id),
      debuff_applications: count(DebuffApplication, encounter_dim_id),
      players: count(PlayerInfo, encounter_dim_id),
      failure_facts: count(FactFailure, encounter_dim_id)
    }
  end

  defp count(schema, encounter_dim_id) do
    schema
    |> where([row], row.encounter_dim_id == ^encounter_dim_id)
    |> Repo.aggregate(:count)
  end

  defp roster(encounter_dim_id) do
    PlayerInfo
    |> where([player], player.encounter_dim_id == ^encounter_dim_id)
    |> order_by([player], asc: player.player_name, asc: player.player_guid)
    |> Repo.all()
    |> Enum.sort_by(&{role_rank(&1.detected_role), String.downcase(&1.player_name || "")})
  end

  defp role_rank("tank"), do: 0
  defp role_rank("healer"), do: 1
  defp role_rank("dps"), do: 2
  defp role_rank(_role), do: 3

  defp deaths(encounter_dim_id) do
    Death
    |> join(:inner, [death], encounter in DimEncounter,
      on: encounter.id == death.encounter_dim_id
    )
    |> join(:left, [death, encounter], player in PlayerInfo,
      on:
        player.encounter_dim_id == death.encounter_dim_id and
          player.player_guid == death.target_guid
    )
    |> where([death, encounter, player], encounter.id == ^encounter_dim_id)
    |> order_by([death, encounter, player],
      asc: death.died_at_ms_into_fight,
      asc: death.target_guid
    )
    |> select([death, encounter, player], %{
      id: death.id,
      target_guid: death.target_guid,
      player_name: player.player_name,
      class_id: player.class_id,
      spec_id: player.spec_id,
      detected_role: player.detected_role,
      died_at_ms_into_fight: death.died_at_ms_into_fight,
      killing_blow_spell_id: death.killing_blow_spell_id,
      killing_blow_source_guid: death.killing_blow_source_guid,
      damage_recap: death.damage_recap,
      encounter_name: encounter.name
    })
    |> Repo.all()
    |> Enum.map(&Map.put(&1, :killing_blow, killing_blow(&1)))
  end

  defp killing_blow(%{damage_recap: [first | _rest]}), do: first
  defp killing_blow(_death), do: nil

  defp interrupt_coverage(encounter_dim_id) do
    rule_failures = interrupt_rule_failures(encounter_dim_id)

    %{
      spell_coverage: interrupt_spell_coverage(encounter_dim_id, rule_failures),
      player_contributions: interrupt_player_contributions(encounter_dim_id)
    }
  end

  defp interrupt_rule_failures(encounter_dim_id) do
    FactFailure
    |> join(:inner, [failure], criterion in DimMechanicCriterion,
      on: criterion.id == failure.criterion_dim_id
    )
    |> where(
      [failure, criterion],
      failure.encounter_dim_id == ^encounter_dim_id and criterion.mechanic_type == "interrupt"
    )
    |> select([failure, criterion], %{
      spell_id: criterion.spell_id,
      spell_name: criterion.spell_name,
      criterion_dim_id: criterion.id,
      failure_count: failure.failure_count
    })
    |> Repo.all()
    |> Enum.group_by(& &1.spell_id)
    |> Map.new(fn {spell_id, rows} ->
      {spell_id,
       %{
         spell_name: rows |> List.first() |> Map.fetch!(:spell_name),
         criterion_dim_ids: Enum.map(rows, & &1.criterion_dim_id),
         failure_count: Enum.sum(Enum.map(rows, & &1.failure_count))
       }}
    end)
  end

  defp interrupt_spell_coverage(encounter_dim_id, rule_failures) do
    InterruptOpportunity
    |> where([row], row.encounter_dim_id == ^encounter_dim_id)
    |> select([row], %{
      interrupted_spell_id: row.interrupted_spell_id,
      success: row.success,
      target_npc_guid: row.target_npc_guid
    })
    |> Repo.all()
    |> Enum.group_by(& &1.interrupted_spell_id)
    |> Enum.map(fn {spell_id, rows} ->
      rule_failure = Map.get(rule_failures, spell_id)
      successes = Enum.count(rows, & &1.success)
      misses = length(rows) - successes

      %{
        spell_id: spell_id,
        spell_name: spell_name(spell_id, rule_failure),
        total_opportunities: length(rows),
        successful_interrupts: successes,
        missed_casts: misses,
        target_count: rows |> Enum.map(& &1.target_npc_guid) |> Enum.uniq() |> length(),
        required_failure_count: rule_failure && rule_failure.failure_count,
        criterion_dim_ids: rule_failure && rule_failure.criterion_dim_ids
      }
    end)
    |> Enum.sort_by(&{-&1.total_opportunities, &1.spell_name, &1.spell_id})
  end

  defp interrupt_player_contributions(encounter_dim_id) do
    InterruptOpportunity
    |> join(:left, [row], player in PlayerInfo,
      on:
        player.encounter_dim_id == row.encounter_dim_id and
          player.player_guid == row.interrupter_guid
    )
    |> where(
      [row, player],
      row.encounter_dim_id == ^encounter_dim_id and row.success == true and
        not is_nil(row.interrupter_guid)
    )
    |> select([row, player], %{
      interrupter_guid: row.interrupter_guid,
      interrupted_spell_id: row.interrupted_spell_id,
      interrupting_spell_id: row.interrupting_spell_id,
      player_name: player.player_name,
      class_id: player.class_id,
      spec_id: player.spec_id,
      detected_role: player.detected_role
    })
    |> Repo.all()
    |> Enum.group_by(& &1.interrupter_guid)
    |> Enum.map(fn {guid, rows} ->
      first = List.first(rows)

      %{
        interrupter_guid: guid,
        player_name: first.player_name,
        class_id: first.class_id,
        spec_id: first.spec_id,
        detected_role: first.detected_role,
        total_interrupts: length(rows),
        interrupted_spell_count:
          rows |> Enum.map(& &1.interrupted_spell_id) |> Enum.uniq() |> length(),
        by_spell: interrupt_player_spell_counts(rows)
      }
    end)
    |> Enum.sort_by(
      &{-&1.total_interrupts, String.downcase(&1.player_name || ""), &1.interrupter_guid}
    )
  end

  defp interrupt_player_spell_counts(rows) do
    rows
    |> Enum.group_by(& &1.interrupted_spell_id)
    |> Enum.map(fn {spell_id, spell_rows} ->
      %{
        spell_id: spell_id,
        spell_name: spell_name(spell_id),
        count: length(spell_rows)
      }
    end)
    |> Enum.sort_by(&{-&1.count, &1.spell_name, &1.spell_id})
  end

  defp spell_name(spell_id, rule_failure \\ nil)

  defp spell_name(_spell_id, %{spell_name: spell_name}) when is_binary(spell_name), do: spell_name

  defp spell_name(spell_id, _rule_failure), do: Spells.name(spell_id)

  defp personal_pull_summary(encounter_dim_id, roster, preferred_character_name) do
    players =
      roster
      |> Enum.map(fn player ->
        Map.merge(
          %{
            player_guid: player.player_guid,
            player_name: player.player_name,
            class_id: player.class_id,
            spec_id: player.spec_id,
            detected_role: player.detected_role
          },
          personal_totals(encounter_dim_id, player.player_guid)
        )
      end)
      |> Enum.sort_by(&{role_rank(&1.detected_role), String.downcase(&1.player_name || "")})

    %{
      selected_player_guid: selected_personal_player_guid(players, preferred_character_name),
      players: players
    }
  end

  defp personal_totals(encounter_dim_id, player_guid) do
    %{}
    |> Map.merge(damage_taken_totals(encounter_dim_id, player_guid))
    |> Map.merge(damage_done_totals(encounter_dim_id, player_guid))
    |> Map.merge(interrupt_totals(encounter_dim_id, player_guid))
    |> Map.merge(death_totals(encounter_dim_id, player_guid))
    |> Map.merge(failure_totals(encounter_dim_id, player_guid))
  end

  defp damage_taken_totals(encounter_dim_id, player_guid) do
    result =
      DamageTaken
      |> where(
        [row],
        row.encounter_dim_id == ^encounter_dim_id and row.target_guid == ^player_guid
      )
      |> select([row], %{
        damage_taken: coalesce(sum(row.total_amount), 0),
        damage_taken_hits: coalesce(sum(row.hit_count), 0),
        max_damage_taken_hit: coalesce(max(row.max_hit), 0),
        overkill_total: coalesce(sum(row.overkill_total), 0)
      })
      |> Repo.one()

    %{
      damage_taken: integer_value(result.damage_taken),
      damage_taken_hits: integer_value(result.damage_taken_hits),
      max_damage_taken_hit: integer_value(result.max_damage_taken_hit),
      overkill_total: integer_value(result.overkill_total)
    }
  end

  defp damage_done_totals(encounter_dim_id, player_guid) do
    result =
      DamageDone
      |> where(
        [row],
        row.encounter_dim_id == ^encounter_dim_id and row.source_guid == ^player_guid
      )
      |> select([row], %{
        damage_done: coalesce(sum(row.total_amount), 0),
        damage_done_hits: coalesce(sum(row.hit_count), 0),
        max_damage_done_hit: coalesce(max(row.max_hit), 0)
      })
      |> Repo.one()

    %{
      damage_done: integer_value(result.damage_done),
      damage_done_hits: integer_value(result.damage_done_hits),
      max_damage_done_hit: integer_value(result.max_damage_done_hit)
    }
  end

  defp interrupt_totals(encounter_dim_id, player_guid) do
    result =
      InterruptOpportunity
      |> where(
        [row],
        row.encounter_dim_id == ^encounter_dim_id and row.interrupter_guid == ^player_guid and
          row.success == true
      )
      |> select([row], %{
        successful_interrupts: count(row.id),
        interrupted_spell_count: count(row.interrupted_spell_id, :distinct)
      })
      |> Repo.one()

    %{
      successful_interrupts: integer_value(result.successful_interrupts),
      interrupted_spell_count: integer_value(result.interrupted_spell_count)
    }
  end

  defp death_totals(encounter_dim_id, player_guid) do
    result =
      Death
      |> where(
        [row],
        row.encounter_dim_id == ^encounter_dim_id and row.target_guid == ^player_guid
      )
      |> select([row], %{
        death_count: count(row.id),
        first_death_ms: min(row.died_at_ms_into_fight)
      })
      |> Repo.one()

    %{
      death_count: integer_value(result.death_count),
      first_death_ms: nullable_integer_value(result.first_death_ms)
    }
  end

  defp failure_totals(encounter_dim_id, player_guid) do
    result =
      FactFailure
      |> join(:inner, [failure], player in assoc(failure, :player))
      |> where(
        [failure, player],
        failure.encounter_dim_id == ^encounter_dim_id and player.player_guid == ^player_guid
      )
      |> select([failure, player], %{
        mechanic_failures: coalesce(sum(failure.failure_count), 0),
        failure_damage: coalesce(sum(failure.total_damage), 0),
        failed_mechanic_count: count(failure.criterion_dim_id, :distinct)
      })
      |> Repo.one()

    %{
      mechanic_failures: integer_value(result.mechanic_failures),
      failure_damage: integer_value(result.failure_damage),
      failed_mechanic_count: integer_value(result.failed_mechanic_count)
    }
  end

  defp integer_value(nil), do: 0
  defp integer_value(%Decimal{} = value), do: Decimal.to_integer(value)
  defp integer_value(value) when is_integer(value), do: value

  defp nullable_integer_value(nil), do: nil
  defp nullable_integer_value(value), do: integer_value(value)

  defp selected_personal_player_guid([], _preferred_character_name), do: nil

  defp selected_personal_player_guid(players, preferred_character_name)
       when is_binary(preferred_character_name) do
    normalized = normalize_name(preferred_character_name)

    case Enum.find(players, &(normalize_name(&1.player_name) == normalized)) do
      %{player_guid: player_guid} -> player_guid
      nil -> selected_personal_player_guid(players, nil)
    end
  end

  defp selected_personal_player_guid([player | _players], _preferred_character_name) do
    player.player_guid
  end

  defp normalize_name(name) when is_binary(name) do
    name
    |> String.split("-")
    |> List.first()
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_name(_name), do: ""

  defp parse_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed_id, ""} when parsed_id > 0 -> {:ok, parsed_id}
      _ -> :error
    end
  end

  defp parse_id(_id), do: :error
end
