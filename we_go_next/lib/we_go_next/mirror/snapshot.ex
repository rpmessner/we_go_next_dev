defmodule WeGoNext.Mirror.Snapshot do
  @moduledoc """
  Encodes per-encounter gold snapshots for public mirror upload.
  """

  import Ecto.Query

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure}
  alias WeGoNext.Repo

  @schema_version 1

  @doc """
  Encodes one encounter's mirrored gold data.
  """
  @spec encode_encounter_snapshot(pos_integer()) :: {:ok, map()} | {:error, term()}
  def encode_encounter_snapshot(encounter_dim_id) when is_integer(encounter_dim_id) do
    with %DimEncounter{} = encounter <- Repo.get(DimEncounter, encounter_dim_id),
         {:ok, source_encounter_key} <- fetch_source_encounter_key(encounter) do
      facts = facts_for_encounter(encounter.id)
      players = players_for_facts(facts)
      criteria = criteria_for_facts(facts)

      {:ok,
       %{
         schema_version: @schema_version,
         encounter: encode_encounter(encounter, source_encounter_key),
         players: Enum.map(players, &encode_player/1),
         criteria: Enum.map(criteria, &encode_criterion/1),
         facts: Enum.map(facts, &encode_fact/1)
       }}
    else
      nil -> {:error, :encounter_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_source_encounter_key(%DimEncounter{id: id, source_encounter_key: nil}) do
    {:error, {:missing_source_encounter_key, id}}
  end

  defp fetch_source_encounter_key(%DimEncounter{source_encounter_key: key}), do: {:ok, key}

  defp facts_for_encounter(encounter_dim_id) do
    FactFailure
    |> where([fact], fact.encounter_dim_id == ^encounter_dim_id)
    |> join(:inner, [fact], player in assoc(fact, :player))
    |> join(:inner, [fact], criterion in assoc(fact, :criterion))
    |> preload([_fact, player, criterion], player: player, criterion: criterion)
    |> order_by([fact, player, criterion], asc: player.player_guid, asc: criterion.criterion_key)
    |> Repo.all()
  end

  defp players_for_facts(facts) do
    facts
    |> Enum.map(& &1.player)
    |> Enum.uniq_by(& &1.player_guid)
    |> Enum.sort_by(& &1.player_guid)
  end

  defp criteria_for_facts(facts) do
    facts
    |> Enum.map(& &1.criterion)
    |> Enum.uniq_by(& &1.criterion_key)
    |> Enum.sort_by(& &1.criterion_key)
  end

  defp encode_encounter(%DimEncounter{} = encounter, source_encounter_key) do
    %{
      source_encounter_key: source_encounter_key,
      wow_encounter_id: encounter.wow_encounter_id,
      name: encounter.name,
      difficulty_id: encounter.difficulty_id,
      difficulty_name: encounter.difficulty_name,
      group_size: encounter.group_size,
      instance_id: encounter.instance_id,
      start_time: encounter.start_time,
      end_time: encounter.end_time,
      success: encounter.success,
      fight_time_ms: encounter.fight_time_ms
    }
  end

  defp encode_player(%DimPlayer{} = player) do
    %{
      player_guid: player.player_guid,
      player_name: player.player_name,
      class_id: player.class_id,
      spec_id: player.spec_id
    }
  end

  defp encode_criterion(%DimMechanicCriterion{} = criterion) do
    %{
      criterion_key: criterion.criterion_key,
      ruleset_id: criterion.ruleset_id,
      ruleset_version: criterion.ruleset_version,
      product: criterion.product,
      channel: criterion.channel,
      build_version: criterion.build_version,
      build_key: criterion.build_key,
      spell_id: criterion.spell_id,
      spell_name: criterion.spell_name,
      mechanic_type: criterion.mechanic_type,
      boss_encounter_id: criterion.boss_encounter_id,
      boss_name: criterion.boss_name,
      difficulty_id: criterion.difficulty_id,
      threshold: criterion.threshold,
      notes: criterion.notes,
      active: criterion.active
    }
  end

  defp encode_fact(%FactFailure{} = fact) do
    %{
      player_guid: fact.player.player_guid,
      criterion_key: fact.criterion.criterion_key,
      ruleset_id: fact.ruleset_id,
      ruleset_version: fact.ruleset_version,
      product: fact.product,
      channel: fact.channel,
      build_version: fact.build_version,
      build_key: fact.build_key,
      derivation_version: fact.derivation_version,
      rebuilt_at: fact.rebuilt_at,
      failure_count: fact.failure_count,
      total_damage: fact.total_damage
    }
  end
end
