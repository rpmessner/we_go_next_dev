defmodule WeGoNext.TrashPull do
  @moduledoc """
  Segments trash events into individual pulls based on combat gaps.

  Takes raw combat events from a trash segment and groups them into
  pulls by detecting periods of no hostile combat activity. Each pull
  gets a list of NPC IDs (mapped to GameData), deaths, and interrupts.
  """

  defstruct [
    :start_time,
    :end_time,
    :duration_seconds,
    events: [],
    npc_ids: [],
    npc_names: [],
    deaths: [],
    interrupts: [],
    missed_casts: [],
    damage_events: 0
  ]

  alias WeGoNext.{CombatLogParser, MythicPlusRun}

  # Gap in seconds between hostile events to consider a new pull
  @pull_gap_seconds 5.0

  # Event types that indicate active combat with enemies
  @hostile_event_types ~w(
    SPELL_DAMAGE SPELL_PERIODIC_DAMAGE SWING_DAMAGE RANGE_DAMAGE
    SPELL_CAST_START SPELL_CAST_SUCCESS SPELL_INTERRUPT
    SPELL_AURA_APPLIED UNIT_DIED
  )

  @doc """
  Parse a trash segment's byte range and split events into pulls.

  Takes a file path and a trash segment map (with start_byte, end_byte,
  start_timestamp) and returns a list of TrashPull structs.
  """
  def segment_pulls(file_path, %{
        start_byte: start_byte,
        end_byte: end_byte,
        start_timestamp: start_ts
      }) do
    case CombatLogParser.parse_events(file_path, start_byte, end_byte, start_ts) do
      {:ok, events} ->
        events
        |> split_by_combat_gaps()
        |> Enum.map(&summarize_pull/1)
        |> Enum.reject(fn pull -> pull.damage_events == 0 and pull.deaths == [] end)

      {:error, _reason} ->
        []
    end
  end

  @doc """
  Parse all trash segments in an M+ run and return pulls grouped by segment.
  """
  def segment_all_pulls(file_path, %MythicPlusRun{} = run) do
    run.trash_segments
    |> Enum.map(fn segment ->
      pulls = segment_pulls(file_path, segment)
      %{segment: segment, pulls: pulls}
    end)
  end

  # Split events into groups separated by combat gaps
  defp split_by_combat_gaps(events) do
    events
    |> Enum.reduce({[], []}, fn event, {current_pull, pulls} ->
      if hostile_event?(event) do
        case current_pull do
          [] ->
            {[event], pulls}

          [prev | _] ->
            gap = event.time_into_fight - prev.time_into_fight

            if gap > @pull_gap_seconds do
              # New pull — save the old one and start fresh
              {[event], [Enum.reverse(current_pull) | pulls]}
            else
              {[event | current_pull], pulls}
            end
        end
      else
        # Non-hostile events get attached to the current pull if one exists
        case current_pull do
          [] -> {[], pulls}
          _ -> {[event | current_pull], pulls}
        end
      end
    end)
    |> then(fn {current_pull, pulls} ->
      case current_pull do
        [] -> Enum.reverse(pulls)
        _ -> Enum.reverse([Enum.reverse(current_pull) | pulls])
      end
    end)
  end

  defp hostile_event?(%{type: type}) when type in @hostile_event_types, do: true
  defp hostile_event?(_), do: false

  # Build a TrashPull struct from a group of events
  defp summarize_pull(events) do
    first = List.first(events)
    last = List.last(events)

    npc_ids =
      events
      |> Enum.flat_map(fn event ->
        source_npc = MythicPlusRun.extract_npc_id(Map.get(event, :source_guid, ""))
        target_npc = MythicPlusRun.extract_npc_id(Map.get(event, :target_guid, ""))
        Enum.reject([source_npc, target_npc], &is_nil/1)
      end)
      |> Enum.uniq()

    npc_names =
      events
      |> Enum.flat_map(fn event ->
        source_guid = Map.get(event, :source_guid, "")
        target_guid = Map.get(event, :target_guid, "")
        source_name = Map.get(event, :source_name, "")
        target_name = Map.get(event, :target_name, "")

        names = []

        names =
          if MythicPlusRun.extract_npc_id(source_guid), do: [source_name | names], else: names

        names =
          if MythicPlusRun.extract_npc_id(target_guid), do: [target_name | names], else: names

        names
      end)
      |> Enum.uniq()

    deaths =
      events
      |> Enum.filter(fn e -> e.type == "UNIT_DIED" end)
      |> Enum.map(fn e ->
        %{
          player_name: Map.get(e, :target_name, "Unknown"),
          player_guid: Map.get(e, :target_guid, ""),
          time_into_fight: e.time_into_fight
        }
      end)

    interrupts =
      events
      |> Enum.filter(fn e -> e.type == "SPELL_INTERRUPT" end)
      |> Enum.map(fn e ->
        %{
          interrupter: Map.get(e, :source_name, "Unknown"),
          interrupted_spell: Map.get(e, :extra_spell_name, "Unknown"),
          interrupted_spell_id: Map.get(e, :extra_spell_id, 0),
          time_into_fight: e.time_into_fight
        }
      end)

    missed_casts =
      find_missed_casts(events)

    damage_count =
      Enum.count(events, fn e ->
        e.type in ~w(SPELL_DAMAGE SPELL_PERIODIC_DAMAGE SWING_DAMAGE RANGE_DAMAGE)
      end)

    %__MODULE__{
      start_time: first && first.time_into_fight,
      end_time: last && last.time_into_fight,
      duration_seconds:
        if(first && last, do: last.time_into_fight - first.time_into_fight, else: 0),
      events: events,
      npc_ids: npc_ids,
      npc_names: npc_names,
      deaths: deaths,
      interrupts: interrupts,
      missed_casts: missed_casts,
      damage_events: damage_count
    }
  end

  # Find enemy casts that completed without being interrupted
  defp find_missed_casts(events) do
    # Collect cast starts and interrupts
    {cast_starts, interrupt_set} =
      Enum.reduce(events, {[], MapSet.new()}, fn event, {casts, ints} ->
        cond do
          event.type == "SPELL_CAST_START" and is_npc_source?(event) ->
            {[event | casts], ints}

          event.type == "SPELL_INTERRUPT" ->
            # The interrupted spell is in extra_spell_id
            key = {Map.get(event, :target_guid, ""), Map.get(event, :extra_spell_id, 0)}
            {casts, MapSet.put(ints, key)}

          true ->
            {casts, ints}
        end
      end)

    # Casts that completed (had SPELL_CAST_SUCCESS) without being interrupted
    cast_successes =
      events
      |> Enum.filter(fn e -> e.type == "SPELL_CAST_SUCCESS" and is_npc_source?(e) end)
      |> Enum.map(fn e -> {Map.get(e, :source_guid, ""), Map.get(e, :spell_id, 0)} end)
      |> MapSet.new()

    # Cast starts that succeeded but weren't interrupted
    cast_starts
    |> Enum.filter(fn e ->
      key = {Map.get(e, :source_guid, ""), Map.get(e, :spell_id, 0)}
      MapSet.member?(cast_successes, key) and not MapSet.member?(interrupt_set, key)
    end)
    |> Enum.map(fn e ->
      %{
        caster: Map.get(e, :source_name, "Unknown"),
        spell_name: Map.get(e, :spell_name, "Unknown"),
        spell_id: Map.get(e, :spell_id, 0),
        time_into_fight: e.time_into_fight
      }
    end)
    |> Enum.uniq_by(fn m -> {m.caster, m.spell_id, Float.round(m.time_into_fight, 0)} end)
  end

  defp is_npc_source?(%{source_guid: guid}) when is_binary(guid) do
    String.starts_with?(guid, "Creature-")
  end

  defp is_npc_source?(_), do: false
end
