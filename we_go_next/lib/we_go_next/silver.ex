defmodule WeGoNext.Silver do
  @moduledoc """
  Public API for projecting and persisting silver medallion rows.
  """

  alias WeGoNext.Gold.DimEncounter
  alias WeGoNext.Repo

  alias WeGoNext.Silver.{
    DamageDone,
    DamageTaken,
    DamageTakenEvent,
    Death,
    DebuffApplication,
    InterruptOpportunity,
    PlayerInfo,
    Projection,
    Projector
  }

  @type persist_result :: %{
          projection: Projection.t(),
          counts: %{atom() => non_neg_integer()}
        }

  @doc """
  Projects and persists silver rows for a gold encounter dimension.

  This API intentionally accepts normalized events directly. Log scanning and
  source file concerns belong in the bronze/log ingestion layer.
  """
  @spec project_and_persist(DimEncounter.t(), keyword()) ::
          {:ok, persist_result()} | {:error, term()}
  def project_and_persist(%DimEncounter{} = dim_encounter, opts) do
    with {:ok, events} <- Keyword.fetch(opts, :events),
         true <- is_list(events),
         projection <- Projector.project(dim_encounter.id, events) do
      persist_projection(projection)
    else
      :error -> {:error, :events_required}
      false -> {:error, :invalid_events}
    end
  end

  defp persist_projection(%Projection{} = projection) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      %{
        damage_taken:
          insert_rows(
            DamageTaken,
            projection.damage_taken,
            now,
            [:encounter_dim_id, :target_guid, :source_guid, :spell_id],
            [:total_amount, :hit_count, :max_hit, :overkill_total, :source_is_npc]
          ),
        damage_taken_event:
          insert_rows(
            DamageTakenEvent,
            projection.damage_taken_event,
            now,
            [:encounter_dim_id, :combat_log_event_index],
            [
              :event_type,
              :occurred_at_ms_into_fight,
              :timestamp,
              :target_guid,
              :target_name,
              :source_guid,
              :source_name,
              :source_is_npc,
              :spell_id,
              :spell_name,
              :spell_school,
              :amount,
              :overkill
            ]
          ),
        damage_done:
          insert_rows(
            DamageDone,
            projection.damage_done,
            now,
            [:encounter_dim_id, :source_guid, :target_guid, :spell_id],
            [:total_amount, :hit_count, :max_hit]
          ),
        death:
          insert_rows(
            Death,
            projection.death,
            now,
            [:encounter_dim_id, :target_guid, :died_at_ms_into_fight],
            [:killing_blow_spell_id, :killing_blow_source_guid, :damage_recap]
          ),
        interrupt_opportunity:
          insert_rows(
            InterruptOpportunity,
            projection.interrupt_opportunity,
            now,
            [
              :encounter_dim_id,
              :target_npc_guid,
              :interrupted_spell_id,
              :opportunity_ms_into_fight
            ],
            [:success, :interrupter_guid, :interrupting_spell_id]
          ),
        debuff_application:
          insert_rows(
            DebuffApplication,
            projection.debuff_application,
            now,
            [:encounter_dim_id, :target_guid, :source_guid, :spell_id, :applied_at_ms_into_fight],
            [:duration_ms, :stack_count]
          ),
        player_info:
          insert_rows(
            PlayerInfo,
            projection.player_info,
            now,
            [:encounter_dim_id, :player_guid],
            [:player_name, :class_id, :spec_id, :item_level, :detected_role]
          )
      }
    end)
    |> case do
      {:ok, counts} -> {:ok, %{projection: projection, counts: counts}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_rows(_schema, [], _now, _conflict_target, _replace_fields), do: 0

  defp insert_rows(schema, rows, now, conflict_target, replace_fields) do
    rows =
      Enum.map(rows, fn row ->
        Map.put(row, :inserted_at, now)
      end)
      |> dedupe_rows(conflict_target)

    {count, _result} =
      Repo.insert_all(
        schema,
        rows,
        on_conflict: {:replace, replace_fields},
        conflict_target: conflict_target
      )

    count
  end

  defp dedupe_rows(rows, conflict_target) do
    rows
    |> Map.new(fn row ->
      key = Enum.map(conflict_target, &Map.fetch!(row, &1))

      {key, row}
    end)
    |> Map.values()
  end
end
