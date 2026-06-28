defmodule WeGoNext.Mirror.Ingest do
  @moduledoc """
  Public mirror ingest for stable-key gold snapshots.
  """

  import Ecto.Query

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure}
  alias WeGoNext.Repo

  @schema_version 1

  @spec upsert_snapshot(map()) :: {:ok, map()} | {:error, term()}
  def upsert_snapshot(snapshot) when is_map(snapshot) do
    with :ok <- validate_schema_version(snapshot),
         {:ok, encounter_attrs} <- encounter_attrs(snapshot),
         {:ok, player_attrs} <- player_attrs(snapshot),
         {:ok, criterion_attrs} <- criterion_attrs(snapshot),
         {:ok, fact_attrs} <- fact_attrs(snapshot) do
      Repo.transaction(fn ->
        encounter = upsert_encounter!(encounter_attrs)
        players_by_guid = upsert_players!(player_attrs)
        criteria_by_key = upsert_criteria!(criterion_attrs)

        {deleted, _} =
          FactFailure
          |> where([fact], fact.encounter_dim_id == ^encounter.id)
          |> Repo.delete_all()

        inserted =
          insert_facts!(
            fact_attrs,
            encounter,
            players_by_guid,
            criteria_by_key
          )

        %{encounter: encounter, deleted: deleted, inserted: inserted}
      end)
    end
  end

  defp validate_schema_version(snapshot) do
    case get(snapshot, :schema_version) do
      @schema_version -> :ok
      version -> {:error, {:unsupported_schema_version, version}}
    end
  end

  defp encounter_attrs(snapshot) do
    case get(snapshot, :encounter) do
      %{} = encounter ->
        {:ok,
         %{
           source_encounter_key: fetch!(encounter, :source_encounter_key),
           wow_encounter_id: fetch!(encounter, :wow_encounter_id),
           name: fetch!(encounter, :name),
           difficulty_id: get(encounter, :difficulty_id),
           difficulty_name: get(encounter, :difficulty_name),
           group_size: get(encounter, :group_size),
           instance_id: get(encounter, :instance_id),
           start_time: parse_datetime(get(encounter, :start_time)),
           end_time: parse_datetime(get(encounter, :end_time)),
           success: get(encounter, :success),
           fight_time_ms: get(encounter, :fight_time_ms)
         }}

      _encounter ->
        {:error, :missing_encounter}
    end
  rescue
    KeyError -> {:error, :invalid_encounter}
  end

  defp player_attrs(snapshot) do
    snapshot
    |> get(:players, [])
    |> Enum.map(fn player ->
      %{
        player_guid: fetch!(player, :player_guid),
        player_name: fetch!(player, :player_name),
        class_id: get(player, :class_id),
        spec_id: get(player, :spec_id)
      }
    end)
    |> then(&{:ok, &1})
  rescue
    KeyError -> {:error, :invalid_players}
  end

  defp criterion_attrs(snapshot) do
    snapshot
    |> get(:criteria, [])
    |> Enum.map(fn criterion ->
      %{
        criterion_key: fetch!(criterion, :criterion_key),
        ruleset_id: fetch!(criterion, :ruleset_id),
        ruleset_version: fetch!(criterion, :ruleset_version),
        product: fetch!(criterion, :product),
        channel: fetch!(criterion, :channel),
        build_version: get(criterion, :build_version),
        build_key: get(criterion, :build_key),
        spell_id: fetch!(criterion, :spell_id),
        spell_name: fetch!(criterion, :spell_name),
        mechanic_type: fetch!(criterion, :mechanic_type),
        boss_encounter_id: get(criterion, :boss_encounter_id),
        boss_name: get(criterion, :boss_name),
        difficulty_id: get(criterion, :difficulty_id),
        threshold: get(criterion, :threshold, %{}),
        notes: get(criterion, :notes),
        active: get(criterion, :active, true)
      }
    end)
    |> then(&{:ok, &1})
  rescue
    KeyError -> {:error, :invalid_criteria}
  end

  defp fact_attrs(snapshot) do
    snapshot
    |> get(:facts, [])
    |> Enum.map(fn fact ->
      %{
        player_guid: fetch!(fact, :player_guid),
        criterion_key: fetch!(fact, :criterion_key),
        ruleset_id: fetch!(fact, :ruleset_id),
        ruleset_version: fetch!(fact, :ruleset_version),
        product: fetch!(fact, :product),
        channel: fetch!(fact, :channel),
        build_version: get(fact, :build_version),
        build_key: get(fact, :build_key),
        derivation_version: get(fact, :derivation_version),
        rebuilt_at: parse_datetime(get(fact, :rebuilt_at)),
        failure_count: fetch!(fact, :failure_count),
        total_damage: fetch!(fact, :total_damage)
      }
    end)
    |> then(&{:ok, &1})
  rescue
    KeyError -> {:error, :invalid_facts}
  end

  defp upsert_encounter!(attrs) do
    %DimEncounter{}
    |> DimEncounter.changeset(attrs)
    |> Repo.insert!(
      on_conflict:
        {:replace,
         [
           :wow_encounter_id,
           :name,
           :difficulty_id,
           :difficulty_name,
           :group_size,
           :instance_id,
           :start_time,
           :end_time,
           :success,
           :fight_time_ms,
           :updated_at
         ]},
      conflict_target: [:source_encounter_key],
      returning: true
    )
  end

  defp upsert_players!(attrs) do
    now = DateTime.utc_now()
    rows = Enum.map(attrs, &Map.merge(&1, %{inserted_at: now, updated_at: now}))

    Repo.insert_all(DimPlayer, rows,
      on_conflict: {:replace, [:player_name, :class_id, :spec_id, :updated_at]},
      conflict_target: [:player_guid]
    )

    guids = Enum.map(attrs, & &1.player_guid)

    DimPlayer
    |> where([player], player.player_guid in ^guids)
    |> Repo.all()
    |> Map.new(&{&1.player_guid, &1})
  end

  defp upsert_criteria!(attrs) do
    Enum.each(attrs, fn attrs ->
      %DimMechanicCriterion{}
      |> DimMechanicCriterion.mirror_changeset(attrs)
      |> Repo.insert!(
        on_conflict:
          {:replace,
           [
             :ruleset_id,
             :ruleset_version,
             :product,
             :channel,
             :build_version,
             :build_key,
             :spell_id,
             :spell_name,
             :mechanic_type,
             :boss_encounter_id,
             :boss_name,
             :difficulty_id,
             :threshold,
             :notes,
             :active,
             :updated_at
           ]},
        conflict_target: [:criterion_key],
        returning: true
      )
    end)

    keys = Enum.map(attrs, & &1.criterion_key)

    DimMechanicCriterion
    |> where([criterion], criterion.criterion_key in ^keys)
    |> Repo.all()
    |> Map.new(&{&1.criterion_key, &1})
  end

  defp insert_facts!(facts, encounter, players_by_guid, criteria_by_key) do
    facts
    |> Enum.map(fn fact ->
      player = Map.fetch!(players_by_guid, fact.player_guid)
      criterion = Map.fetch!(criteria_by_key, fact.criterion_key)

      %FactFailure{}
      |> FactFailure.changeset(%{
        encounter_dim_id: encounter.id,
        player_dim_id: player.id,
        criterion_dim_id: criterion.id,
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
      })
      |> Repo.insert!()
    end)
    |> length()
  end

  defp get(map, key, default \\ nil) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp fetch!(map, key) do
    if has_key?(map, key), do: get(map, key), else: raise(KeyError, key: key, term: map)
  end

  defp has_key?(map, key), do: Map.has_key?(map, key) or Map.has_key?(map, Atom.to_string(key))

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = datetime), do: datetime

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end
end
