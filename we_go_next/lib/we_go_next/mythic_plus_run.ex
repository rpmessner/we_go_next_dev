defmodule WeGoNext.MythicPlusRun do
  @moduledoc """
  Groups scan_boundaries output into M+ run sessions.

  A run is everything between a CHALLENGE_MODE_START and its matching
  CHALLENGE_MODE_END. Within a run, there are boss encounters and trash
  segments (the byte gaps between encounters).
  """

  defstruct [
    :name,
    :instance_id,
    :challenge_mode_id,
    :keystone_level,
    :start_byte,
    :end_byte,
    :start_timestamp,
    :end_timestamp,
    :success,
    :total_time_ms,
    encounters: [],
    trash_segments: []
  ]

  @doc """
  Takes a list of boundaries from scan_boundaries and returns a list of
  MythicPlusRun structs with encounters and trash segments grouped.

  Boundaries with `success=false, keystone_level=0` CM_END events are
  filtered out (these are "leaving previous dungeon" markers).
  """
  def from_boundaries(boundaries) do
    boundaries
    |> group_runs([])
    |> Enum.map(&compute_trash_segments/1)
    |> Enum.reverse()
  end

  # Walk through boundaries, accumulating encounters into runs
  defp group_runs([], acc), do: acc

  defp group_runs([%{boundary_type: :challenge_mode_start} = cm_start | rest], acc) do
    {encounters, remaining} = collect_until_cm_end(rest, [])

    case remaining do
      [%{boundary_type: :challenge_mode_end} = cm_end | tail] ->
        run = %__MODULE__{
          name: cm_start.name,
          instance_id: cm_start.instance_id,
          challenge_mode_id: cm_start.challenge_mode_id,
          keystone_level: cm_start.keystone_level,
          start_byte: cm_start.start_byte,
          start_timestamp: cm_start.start_timestamp,
          end_byte: cm_end.end_byte,
          end_timestamp: cm_end.end_timestamp,
          success: cm_end.success,
          total_time_ms: cm_end.total_time_ms,
          encounters: Enum.reverse(encounters)
        }

        group_runs(tail, [run | acc])

      _ ->
        # CM_START without matching CM_END (incomplete run, e.g. log ended mid-key)
        run = %__MODULE__{
          name: cm_start.name,
          instance_id: cm_start.instance_id,
          challenge_mode_id: cm_start.challenge_mode_id,
          keystone_level: cm_start.keystone_level,
          start_byte: cm_start.start_byte,
          start_timestamp: cm_start.start_timestamp,
          encounters: Enum.reverse(encounters)
        }

        group_runs(remaining, [run | acc])
    end
  end

  # Skip non-CM_START boundaries at the top level (encounters outside M+, stale CM_ENDs)
  defp group_runs([_other | rest], acc) do
    group_runs(rest, acc)
  end

  # Collect encounter boundaries until we hit a real CM_END (not a level=0 reset marker)
  defp collect_until_cm_end([], acc), do: {acc, []}

  defp collect_until_cm_end(
         [%{boundary_type: :challenge_mode_end, keystone_level: 0} | rest],
         acc
       ) do
    # Skip the "leaving dungeon" CM_END markers (success=false, level=0)
    collect_until_cm_end(rest, acc)
  end

  defp collect_until_cm_end(
         [%{boundary_type: :challenge_mode_end} | _] = rest,
         acc
       ) do
    # Real CM_END — stop collecting
    {acc, rest}
  end

  defp collect_until_cm_end(
         [%{boundary_type: :challenge_mode_start} | _] = rest,
         acc
       ) do
    # Another CM_START before CM_END — the previous run was abandoned
    {acc, rest}
  end

  defp collect_until_cm_end([%{boundary_type: :encounter} = enc | rest], acc) do
    collect_until_cm_end(rest, [enc | acc])
  end

  defp collect_until_cm_end([_other | rest], acc) do
    collect_until_cm_end(rest, acc)
  end

  # Compute trash segments — the byte gaps between encounters within the run
  defp compute_trash_segments(%__MODULE__{} = run) do
    segments =
      build_trash_segments(
        run.start_byte,
        run.start_timestamp,
        run.encounters,
        run.end_byte,
        run.end_timestamp
      )

    %{run | trash_segments: segments}
  end

  defp build_trash_segments(run_start_byte, run_start_ts, encounters, run_end_byte, run_end_ts) do
    # Generate trash segments for the gaps between encounters
    # Trash 1: CM_START → first encounter
    # Trash 2: first encounter end → second encounter start
    # ...
    # Trash N: last encounter end → CM_END

    case encounters do
      [] ->
        # No encounters — entire run is trash (or very short key)
        if run_end_byte do
          [
            %{
              start_byte: run_start_byte,
              end_byte: run_end_byte,
              start_timestamp: run_start_ts,
              end_timestamp: run_end_ts,
              label: "Trash"
            }
          ]
        else
          []
        end

      encounters ->
        first = hd(encounters)
        last = List.last(encounters)

        before_first =
          if first.start_byte > run_start_byte do
            [
              %{
                start_byte: run_start_byte,
                end_byte: first.start_byte,
                start_timestamp: run_start_ts,
                end_timestamp: first.start_timestamp,
                label: "Trash (before #{first.name})"
              }
            ]
          else
            []
          end

        between =
          encounters
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.flat_map(fn [prev, next] ->
            if next.start_byte > prev.end_byte do
              [
                %{
                  start_byte: prev.end_byte,
                  end_byte: next.start_byte,
                  start_timestamp: prev.end_timestamp,
                  end_timestamp: next.start_timestamp,
                  label: "Trash (#{prev.name} → #{next.name})"
                }
              ]
            else
              []
            end
          end)

        after_last =
          if run_end_byte && last.end_byte < run_end_byte do
            [
              %{
                start_byte: last.end_byte,
                end_byte: run_end_byte,
                start_timestamp: last.end_timestamp,
                end_timestamp: run_end_ts,
                label: "Trash (after #{last.name})"
              }
            ]
          else
            []
          end

        before_first ++ between ++ after_last
    end
  end

  @doc """
  Extract the NPC ID from a WoW creature GUID.

  Format: Creature-0-serverID-instanceID-zoneUID-npcID-spawnUID
  Returns the npcID as an integer, or nil if not a creature GUID.
  """
  def extract_npc_id("Creature-" <> rest) do
    case String.split(rest, "-") do
      [_, _, _, _, npc_id_str, _] ->
        case Integer.parse(npc_id_str) do
          {npc_id, ""} -> npc_id
          _ -> nil
        end

      _ ->
        nil
    end
  end

  def extract_npc_id(_), do: nil
end
