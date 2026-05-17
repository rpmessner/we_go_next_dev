defmodule WeGoNext.Silver do
  @moduledoc """
  Public API for projecting and persisting silver medallion rows.
  """

  alias WeGoNext.CombatLogFile
  alias WeGoNext.CombatLogParser
  alias WeGoNext.Encounters.Encounter, as: EncounterRecord
  alias WeGoNext.Repo

  alias WeGoNext.Silver.{
    DamageDone,
    DamageTaken,
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
  Parses, projects, and persists silver rows for an encounter.

  The default path parses normalized events from the encounter byte range using
  `CombatLogParser.parse_events/4`. Tests may pass `events: events` to exercise
  the persistence layer without depending on combat-log text fixtures.
  """
  @spec project_and_persist(EncounterRecord.t(), keyword()) ::
          {:ok, persist_result()} | {:error, term()}
  def project_and_persist(%EncounterRecord{} = encounter, opts \\ []) do
    with {:ok, events} <- events_for_encounter(encounter, opts),
         projection <- Projector.project(encounter.id, events) do
      persist_projection(projection)
    end
  end

  defp events_for_encounter(%EncounterRecord{} = encounter, opts) do
    case Keyword.fetch(opts, :events) do
      {:ok, events} when is_list(events) ->
        {:ok, events}

      :error ->
        combat_log_file = Repo.get!(CombatLogFile, encounter.combat_log_file_id)

        CombatLogParser.parse_events(
          combat_log_file.file_path,
          encounter.start_byte,
          encounter.end_byte,
          format_timestamp(encounter.start_time)
        )
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
            [:encounter_id, :target_guid, :source_guid, :spell_id],
            [:total_amount, :hit_count, :max_hit, :overkill_total, :source_is_npc]
          ),
        damage_done:
          insert_rows(
            DamageDone,
            projection.damage_done,
            now,
            [:encounter_id, :source_guid, :target_guid, :spell_id],
            [:total_amount, :hit_count, :max_hit]
          ),
        death:
          insert_rows(
            Death,
            projection.death,
            now,
            [:encounter_id, :target_guid, :died_at_ms_into_fight],
            [:killing_blow_spell_id, :killing_blow_source_guid, :damage_recap]
          ),
        interrupt_opportunity:
          insert_rows(
            InterruptOpportunity,
            projection.interrupt_opportunity,
            now,
            [:encounter_id, :target_npc_guid, :interrupted_spell_id, :opportunity_ms_into_fight],
            [:success, :interrupter_guid, :interrupting_spell_id]
          ),
        debuff_application:
          insert_rows(
            DebuffApplication,
            projection.debuff_application,
            now,
            [:encounter_id, :target_guid, :source_guid, :spell_id, :applied_at_ms_into_fight],
            [:duration_ms, :stack_count]
          ),
        player_info:
          insert_rows(
            PlayerInfo,
            projection.player_info,
            now,
            [:encounter_id, :player_guid],
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

    {count, _result} =
      Repo.insert_all(
        schema,
        rows,
        on_conflict: {:replace, replace_fields},
        conflict_target: conflict_target
      )

    count
  end

  defp format_timestamp(%DateTime{} = dt) do
    ms = div(elem(dt.microsecond, 0), 1000)

    "#{dt.month}/#{dt.day}/#{dt.year} #{String.pad_leading("#{dt.hour}", 2, "0")}:#{String.pad_leading("#{dt.minute}", 2, "0")}:#{String.pad_leading("#{dt.second}", 2, "0")}.#{ms}-0"
  end

  defp format_timestamp(%NaiveDateTime{} = dt) do
    ms = div(elem(dt.microsecond, 0), 1000)

    "#{dt.month}/#{dt.day}/#{dt.year} #{String.pad_leading("#{dt.hour}", 2, "0")}:#{String.pad_leading("#{dt.minute}", 2, "0")}:#{String.pad_leading("#{dt.second}", 2, "0")}.#{ms}-0"
  end

  defp format_timestamp(nil), do: "1/1/2000 00:00:00.000-0"
end
