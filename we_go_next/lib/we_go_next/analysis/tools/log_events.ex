defmodule WeGoNext.Analysis.Tools.LogEvents do
  @moduledoc "Filtered, uncached bronze events from one session-scoped gold pull."
  @behaviour WeGoNext.Analysis.Tool
  alias WeGoNext.Analysis.{ReadModel, Result, Tool}
  alias WeGoNext.Analysis.Tools.SilverPulls
  alias WeGoNext.{CombatLogParser, Repo}
  alias WeGoNext.Gold.DimEncounter

  @filter_keys [
    :event_types,
    :source_guids,
    :target_guids,
    :spell_ids,
    :time_min_ms,
    :time_max_ms
  ]

  def name, do: "log_events"

  def description do
    "Escape hatch for defensives, consumables, casts, auras and resources not answered by silver/gold. Re-parses only one gold pull's bronze byte range, without caching. Supply at least one nonempty selective filter or a time window narrower than the pull. Lists OR within each filter; filters AND across. Time bounds are inclusive integer milliseconds relative to pull start. Names/GUIDs are unaliased; spell_ids matches the primary spell, not interrupt extra spells. Follow next_cursor with identical arguments. Raw observations alone do not establish cooldown availability."
  end

  def input_schema do
    schema =
      Tool.schema(%{
        "pull" => %{"type" => "integer", "minimum" => 1},
        "filters" => %{
          "type" => "object",
          "additionalProperties" => false,
          "properties" => %{
            "event_types" => strings(),
            "source_guids" => strings(),
            "target_guids" => strings(),
            "spell_ids" => %{
              "type" => "array",
              "minItems" => 1,
              "maxItems" => 100,
              "items" => %{"type" => "integer", "minimum" => 0}
            },
            "time_min_ms" => %{
              "type" => "integer",
              "minimum" => 0,
              "description" => "Inclusive lower bound, milliseconds relative to pull start."
            },
            "time_max_ms" => %{
              "type" => "integer",
              "minimum" => 0,
              "description" => "Inclusive upper bound, milliseconds relative to pull start."
            }
          }
        }
      })

    Map.update!(schema, "required", &(&1 ++ ["pull", "filters"]))
  end

  def run(args, context) do
    with {:ok, _} <- SilverPulls.select(%{"pulls" => [args["pull"]]}, context),
         dim = Repo.get!(DimEncounter, args["pull"]),
         :ok <- valid_range(dim),
         filters = native_filters(args["filters"]),
         :ok <- selective(filters, dim),
         path = ReadModel.log(context).file_path,
         {:ok, origin} <- origin(path, dim),
         {:ok, events} <- parse(path, dim, origin, filters) do
      rows =
        Enum.map(events, fn event ->
          {event,
           %{
             pull_id: dim.id,
             timestamp: event.timestamp,
             byte_offset: event.byte_offset,
             source: "bronze.combat_log"
           }}
        end)

      Result.page(rows, args, {name(), context.id})
    end
  end

  defp strings do
    %{
      "type" => "array",
      "minItems" => 1,
      "maxItems" => 100,
      "items" => %{"type" => "string", "minLength" => 1}
    }
  end

  defp native_filters(filters) do
    for key <- @filter_keys,
        Map.has_key?(filters, Atom.to_string(key)),
        into: %{},
        do: {key, filters[Atom.to_string(key)]}
  end

  defp valid_range(%{start_byte: start, end_byte: finish})
       when is_integer(start) and start >= 0 and is_integer(finish) and finish > start, do: :ok

  defp valid_range(_),
    do: {:error, "Pull has no complete gold byte range; import a finished pull first"}

  defp selective(filters, dim) do
    low = filters[:time_min_ms] || 0
    high = filters[:time_max_ms]
    duration = dim.fight_time_ms || duration(dim)
    selective_list = Enum.any?(Enum.take(@filter_keys, 4), &(Map.get(filters, &1, []) != []))
    narrow_time = narrow_time?(low, high, duration)

    cond do
      is_integer(high) and high < low ->
        {:error, "time_max_ms must be >= time_min_ms"}

      selective_list or narrow_time ->
        :ok

      true ->
        {:error,
         "Narrow log_events with event_types, source_guids, target_guids, spell_ids, or a time window shorter than the pull"}
    end
  end

  defp narrow_time?(low, _high, _duration) when low > 0, do: true

  defp narrow_time?(_low, high, duration) when is_integer(high) and is_integer(duration),
    do: high < duration

  defp narrow_time?(_low, _high, _duration), do: false

  defp duration(%{start_time: %DateTime{} = start, end_time: %DateTime{} = finish}),
    do: DateTime.diff(finish, start, :millisecond)

  defp duration(_), do: nil

  # The NIF ignores timezone offsets. Read the original wall-clock timestamp at
  # the gold start byte rather than formatting the dimension's UTC start_time.
  defp origin(path, dim) do
    case File.open(path, [:read, :binary]) do
      {:ok, file} ->
        try do
          with {:ok, %{size: size, type: :regular}} <- File.stat(path),
               true <- size >= dim.end_byte,
               {:ok, prefix} <-
                 :file.pread(file, dim.start_byte, min(256, dim.end_byte - dim.start_byte)),
               [timestamp, _] <- String.split(prefix, "  ", parts: 2) do
            {:ok, timestamp}
          else
            _ ->
              {:error,
               "Cannot read pull byte range from combat log #{path}; file is truncated or invalid"}
          end
        after
          File.close(file)
        end

      {:error, reason} ->
        {:error, "Cannot read combat log #{path}: #{:file.format_error(reason)}"}
    end
  end

  defp parse(path, dim, origin, filters) do
    case CombatLogParser.parse_events_filtered(
           path,
           dim.start_byte,
           dim.end_byte,
           origin,
           filters
         ) do
      {:ok, events} -> {:ok, events}
      {:error, reason} -> {:error, "Cannot parse combat log #{path}: #{inspect(reason)}"}
    end
  end
end
