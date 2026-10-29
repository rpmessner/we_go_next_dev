# From we_go_next/: mix run --no-start ../docs/research/scripts/nif_filtered_bench.exs /tmp/wgn-nif-090626.txt
# Copy the Sept 6 archive to local disk first. No DB or app is started.
# Optional second argument: path to the pre-change Zig source, for exact import equality.
[path | rest] = System.argv()
alias WeGoNext.CombatLogParser, as: Parser
start_byte = 1_056_119_869
end_byte = 1_167_985_096
{:ok, file} = File.open(path, [:read, :binary])
{:ok, first} = :file.pread(file, start_byte, 128)
File.close(file)
[timestamp | _] = String.split(first, "  ", parts: 2)

measure = fn label, fun ->
  for run <- 1..3 do
    :erlang.garbage_collect()
    {us, {:ok, events}} = :timer.tc(fun)
    IO.puts("#{label}\t#{run}\t#{Float.round(us / 1000, 3)} ms\t#{length(events)} events")
  end
end

{:ok, all} = Parser.parse_events(path, start_byte, end_byte, timestamp)
IO.puts("Twin Fangs bytes #{start_byte}-#{end_byte}, timestamp #{timestamp}")
IO.puts("import events: #{length(all)}")

if rest != [] do
  baseline_path = hd(rest)

  Code.eval_string("""
  defmodule Bench.ImportBaseline do
    use Zig,
      otp_app: :we_go_next,
      zig_code_path: #{inspect(baseline_path)},
      optimize: :safe,
      nifs: [scan_boundaries: [spec: false, concurrency: :dirty_cpu], parse_events: [spec: false, concurrency: :dirty_cpu]]
  end
  """)

  File.rm!(".Elixir.Bench.ImportBaseline.zig")
  {:ok, baseline} = Bench.ImportBaseline.parse_events(path, start_byte, end_byte, timestamp)
  true = baseline == all
  IO.puts("pre-change parse_events/4 exact real-pull equality PASS (#{length(all)} events)")
end

{:ok, unfiltered} = Parser.parse_events_filtered(path, start_byte, end_byte, timestamp, %{})
true = Enum.map(unfiltered, &Map.delete(&1, :byte_offset)) == all
IO.puts("filtered empty-map vs import equality PASS")

player =
  all
  |> Enum.filter(
    &(is_binary(&1[:target_guid]) and String.starts_with?(&1[:target_guid], "Player-"))
  )
  |> Enum.frequencies_by(& &1.target_guid)
  |> Enum.max_by(&elem(&1, 1))
  |> elem(0)

spell =
  all
  |> Enum.filter(&(&1.type == "SPELL_DAMAGE" and &1[:target_guid] == player))
  |> Enum.frequencies_by(& &1.spell_id)
  |> Enum.max_by(&elem(&1, 1))
  |> elem(0)

measure.("unfiltered import", fn -> Parser.parse_events(path, start_byte, end_byte, timestamp) end)

for {label, filters} <- [
      {"UNIT_DIED", %{event_types: ["UNIT_DIED"]}},
      {"target #{player}", %{target_guids: [player]}},
      {"spell #{spell}", %{spell_ids: [spell]}},
      {"combined",
       %{
         event_types: ["SPELL_DAMAGE"],
         target_guids: [player],
         spell_ids: [spell],
         time_min_ms: 100_000,
         time_max_ms: 130_000
       }}
    ] do
  measure.(label, fn ->
    Parser.parse_events_filtered(path, start_byte, end_byte, timestamp, filters)
  end)
end
