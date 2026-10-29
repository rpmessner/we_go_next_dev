# Bronze read-path benchmark for we-c5q.3 (Tool read paths).
#
# Read-only: touches no database. Run from we_go_next/:
#
#   mix run --no-start ../docs/research/scripts/bronze_bench.exs <log path> [safe] [skip_scan]
#
# - Without `safe`, uses WeGoNext.CombatLogParser as built for MIX_ENV=dev
#   (zigler default: Zig Debug mode, synchronous NIF).
# - With `safe`, compiles the same Zig source as Bench.ParserSafe in
#   ReleaseSafe mode (zigler's default outside dev/test).
#
# Measures: full-file scan_boundaries, per-encounter parse_events (seek + read
# + normalize), resulting term size, a filtered slice, and in-memory silver
# projection.

[path | flags] = System.argv()
safe? = "safe" in flags
skip_scan? = "skip_scan" in flags

parser =
  if safe? do
    defmodule Bench.ParserSafe do
      use Zig,
        otp_app: :we_go_next,
        zig_code_path: "./priv/native/combat_log_parser.zig",
        optimize: :safe,
        nifs: [scan_boundaries: [spec: false], parse_events: [spec: false]]
    end

    Bench.ParserSafe
  else
    WeGoNext.CombatLogParser
  end

ms = fn us -> Float.round(us / 1000, 1) end
mb = fn bytes -> Float.round(bytes / 1_048_576, 1) end

IO.puts("file=#{path} size=#{mb.(File.stat!(path).size)}MB parser=#{inspect(parser)}")

# 1. Boundary scan over the whole file (what an index lookup would replace).
boundaries =
  if skip_scan? do
    nil
  else
    {scan_us, {:ok, boundaries, end_byte}} =
      :timer.tc(fn -> parser.scan_boundaries(path, 0) end)

    IO.puts(
      "scan_boundaries full file: #{ms.(scan_us)} ms, #{length(boundaries)} boundaries, end_byte=#{end_byte}"
    )

    boundaries
  end

boundaries =
  boundaries ||
    (fn ->
       {:ok, b, _} = WeGoNext.CombatLogParser.scan_boundaries(path, 0)
       b
     end).()

encounters =
  boundaries
  |> Enum.filter(&Map.has_key?(&1, :wow_encounter_id))
  |> Enum.map(&Map.put(&1, :bytes, &1.end_byte - &1.start_byte))

sorted = Enum.sort_by(encounters, & &1.bytes)

IO.puts(
  "encounter pulls=#{length(encounters)} bytes min=#{mb.(hd(sorted).bytes)}MB " <>
    "median=#{mb.(Enum.at(sorted, div(length(sorted), 2)).bytes)}MB max=#{mb.(List.last(sorted).bytes)}MB " <>
    "sum=#{mb.(Enum.sum(Enum.map(sorted, & &1.bytes)))}MB"
)

picks = [
  {"largest", List.last(sorted)},
  {"median", Enum.at(sorted, div(length(sorted), 2))},
  {"smallest", hd(sorted)}
]

for {label, enc} <- picks do
  # The NIF ignores the TZ suffix of the start timestamp.
  start_ts = enc.start_timestamp

  # Runs 1-2 discard their result (timing only); run 3 is kept for size and
  # downstream measurements, so the memory delta reflects one parsed encounter.
  runs =
    for run <- 1..2 do
      {us, {:ok, _events}} =
        :timer.tc(fn -> parser.parse_events(path, enc.start_byte, enc.end_byte, start_ts) end)

      :erlang.garbage_collect()
      {run, us, nil}
    end

  :erlang.garbage_collect()
  before_total = :erlang.memory(:total)

  {us3, {:ok, events}} =
    :timer.tc(fn -> parser.parse_events(path, enc.start_byte, enc.end_byte, start_ts) end)

  runs = runs ++ [{3, us3, nil}]
  after_total = :erlang.memory(:total)
  words = :erts_debug.flat_size(events)

  IO.puts(
    "[#{label}] #{enc.name} diff=#{enc.difficulty_id} fight=#{div(enc.fight_time_ms, 1000)}s " <>
      "bytes=#{mb.(enc.bytes)}MB events=#{length(events)} " <>
      "parse runs ms=#{Enum.map_join(runs, ",", fn {_, us, _} -> ms.(us) end)} " <>
      "term_size=#{mb.(words * 8)}MB beam_total_delta=#{mb.(after_total - before_total)}MB"
  )

  if label == "largest" do
    by_type =
      events
      |> Enum.frequencies_by(& &1[:type])
      |> Enum.sort_by(&elem(&1, 1), :desc)
      |> Enum.take(8)

    IO.puts("  top event types: #{inspect(by_type)}")

    # A typical Tool slice: hits on one player from one spell in a 30s window.
    sample =
      Enum.find(events, fn e ->
        e[:type] == "SPELL_DAMAGE" and is_binary(e[:target_guid]) and
          String.starts_with?(e[:target_guid], "Player-")
      end)

    {filter_us, slice} =
      :timer.tc(fn ->
        t0 = sample[:time_into_fight]

        Enum.filter(events, fn e ->
          e[:target_guid] == sample[:target_guid] and e[:spell_id] == sample[:spell_id] and
            e[:time_into_fight] >= t0 and e[:time_into_fight] < t0 + 30.0
        end)
      end)

    IO.puts("  filter slice (target+spell+30s window): #{ms.(filter_us)} ms -> #{length(slice)} events")

    {proj_us, projection} = :timer.tc(fn -> WeGoNext.Silver.Projector.project(1, events) end)

    counts =
      projection
      |> Map.from_struct()
      |> Enum.map(fn {k, v} -> {k, length(v)} end)

    IO.puts("  in-memory silver projection: #{ms.(proj_us)} ms #{inspect(counts)}")
    IO.puts("  sample keys: #{inspect(Map.keys(hd(events)))}")
  end
end
