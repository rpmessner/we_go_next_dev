# Prototype measurement for we-c5q.3: how much does filtering *inside* the NIF
# save versus parse-everything-then-Enum.filter?
#
# Read-only. Does not modify priv/native: it copies combat_log_parser.zig to a
# scratch dir, adds a 5th `needle` argument to parse_events, and skips any line
# that does not contain the needle before building Erlang terms (the expensive
# part). Built in ReleaseSafe. Run from we_go_next/:
#
#   mix run --no-start ../docs/research/scripts/bronze_filter_bench.exs <log path> <scratch dir>
#
# The needle is a substring prefilter (a GUID, a spell id like ",1214081,", or
# an event type). A real Tool would still apply an exact field filter after it.

[path, scratch] = System.argv()

src = File.read!("priv/native/combat_log_parser.zig")

patched =
  src
  |> String.replace(
    "pub fn parse_events(file_path_term: beam.term, start_byte_term: beam.term, end_byte_term: beam.term, start_ts_term: beam.term) beam.term {\n    const env = beam.context.env orelse unreachable;\n",
    "pub fn parse_events(file_path_term: beam.term, start_byte_term: beam.term, end_byte_term: beam.term, start_ts_term: beam.term, needle_term: beam.term) beam.term {\n    const env = beam.context.env orelse unreachable;\n    const needle = beam.get([]const u8, needle_term, .{}) catch {\n        return make_error_tuple(env, \"invalid_needle\");\n    };\n"
  )
  |> String.replace(
    "            if (line.len > 10) {",
    "            if (line.len > 10 and (needle.len == 0 or std.mem.indexOf(u8, line, needle) != null)) {"
  )

true = patched != src
File.mkdir_p!(scratch)
zig_path = Path.join(scratch, "combat_log_parser_filtered.zig")
File.write!(zig_path, patched)

Code.eval_string("""
defmodule Bench.ParserFiltered do
  use Zig,
    otp_app: :we_go_next,
    zig_code_path: #{inspect(zig_path)},
    optimize: :safe,
    nifs: [scan_boundaries: [spec: false], parse_events: [spec: false]]
end
""")

ms = fn us -> Float.round(us / 1000, 1) end
mb = fn bytes -> Float.round(bytes / 1_048_576, 1) end

{scan_us, {:ok, boundaries, _}} = :timer.tc(fn -> Bench.ParserFiltered.scan_boundaries(path, 0) end)
IO.puts("scan_boundaries: #{ms.(scan_us)} ms")

enc =
  boundaries
  |> Enum.filter(&Map.has_key?(&1, :wow_encounter_id))
  |> Enum.max_by(&(&1.end_byte - &1.start_byte))

IO.puts("pull: #{enc.name} #{mb.(enc.end_byte - enc.start_byte)}MB")

parse = fn needle ->
  :erlang.garbage_collect()

  times =
    for _ <- 1..3 do
      {us, {:ok, events}} =
        :timer.tc(fn ->
          Bench.ParserFiltered.parse_events(path, enc.start_byte, enc.end_byte, enc.start_timestamp, needle)
        end)

      {us, events}
    end

  {_, events} = List.last(times)
  {Enum.map(times, &elem(&1, 0)), events}
end

{all_times, all} = parse.("")
IO.puts("no filter: ms=#{Enum.map_join(all_times, ",", ms)} events=#{length(all)}")

# Pick needles from the parsed data: the most-hit player, the top damage-taken
# spell on players, and a rare event type.
player =
  all
  |> Enum.filter(&(is_binary(&1[:target_guid]) and String.starts_with?(&1[:target_guid], "Player-")))
  |> Enum.frequencies_by(& &1[:target_guid])
  |> Enum.max_by(&elem(&1, 1))
  |> elem(0)

spell =
  all
  |> Enum.filter(
    &(&1[:type] in ["SPELL_DAMAGE", "SPELL_PERIODIC_DAMAGE"] and is_binary(&1[:target_guid]) and
        String.starts_with?(&1[:target_guid], "Player-") and is_binary(&1[:source_guid]) and
        String.starts_with?(&1[:source_guid], "Creature-"))
  )
  |> Enum.frequencies_by(& &1[:spell_id])
  |> Enum.max_by(&elem(&1, 1))
  |> elem(0)

all = nil
_ = all

for {label, needle} <- [
      {"player guid", player},
      {"npc spell id", ",#{spell},"},
      {"UNIT_DIED", "UNIT_DIED"}
    ] do
  {times, events} = parse.(needle)

  IO.puts(
    "needle #{label} (#{needle}): ms=#{Enum.map_join(times, ",", ms)} events=#{length(events)} " <>
      "term=#{mb.(:erts_debug.flat_size(events) * 8)}MB"
  )
end
