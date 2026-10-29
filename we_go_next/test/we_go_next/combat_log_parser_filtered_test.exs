defmodule WeGoNext.CombatLogParserFilteredTest do
  use ExUnit.Case, async: true

  alias WeGoNext.CombatLogParser, as: Parser

  @path Path.expand("../fixtures/pet_attribution_real_pull.txt", __DIR__)
  @timestamp "8/19/2026 21:22:10.312-4"

  test "filters exact event types before returning events with file byte offsets" do
    assert {:ok, [event]} = parse(%{event_types: ["SPELL_SUMMON"]})
    assert event.type == "SPELL_SUMMON"
    assert event.spell_id == 1_276_452
    {:ok, file} = File.open(@path, [:read, :binary])

    assert {:ok, "8/19/2026 21:22:11.532-4  SPELL_SUMMON,"} =
             :file.pread(file, event.byte_offset, 39)

    File.close(file)
  end

  test "source GUID matches only the source, not the advanced owner GUID" do
    assert {:ok, [event]} = parse(%{source_guids: ["Player-1175-0FF05A1A"]})
    assert event.type == "SPELL_SUMMON"
  end

  test "target GUID matches only the target" do
    assert {:ok, [event]} =
             parse(%{target_guids: ["Creature-0-3023-3004-53803-258584-00000656C2"]})

    assert event.type == "SPELL_SUMMON"
  end

  test "spell ids match the spell field, including the synthetic melee id zero" do
    assert {:ok, [event]} = parse(%{spell_ids: [89_753]})
    assert event.spell_name == "Felstorm"
    assert {:ok, [melee]} = parse(%{spell_ids: [0]})
    assert melee.type == "SWING_DAMAGE"
  end

  test "time window is inclusive pull-relative milliseconds" do
    assert {:ok, [event]} = parse(%{time_min_ms: 2_499, time_max_ms: 2_499})
    assert event.type == "SWING_DAMAGE"
    assert event.time_into_fight == 2.499
    assert {:ok, before} = parse(%{time_max_ms: 2_499})
    assert length(before) == 3
    assert {:ok, after_window} = parse(%{time_min_ms: 2_499})
    assert length(after_window) == 3
  end

  test "filters compose with AND and list values with OR" do
    assert {:ok, [event]} =
             parse(%{
               event_types: ["SPELL_DAMAGE", "SPELL_SUMMON"],
               source_guids: ["not-a-source", "Pet-0-3023-3004-53803-17252-020579123C"],
               target_guids: ["Creature-0-3023-3004-53803-257368-0000065653"],
               spell_ids: [89_753, 52_212],
               time_min_ms: 3_124,
               time_max_ms: 3_124
             })

    assert event.spell_name == "Felstorm"
  end

  test "no match returns an empty result" do
    assert {:ok, []} = parse(%{event_types: ["SPELL_DAMAGE"], spell_ids: [1_276_452]})
    assert {:ok, []} = parse(%{source_guids: ["Player-1175-0FF05A1"]})
    assert {:ok, []} = parse(%{time_min_ms: 10_000})
  end

  test "real fixtures equal import events filtered in Elixir, without changing import maps" do
    for fixture <- [
          "pet_attribution_real_pull.txt",
          "survival_actions_real_pull.txt",
          "combat_log_base.txt"
        ] do
      path = Path.expand("../fixtures/#{fixture}", __DIR__)
      size = File.stat!(path).size
      assert {:ok, all} = Parser.parse_events(path, 0, size, @timestamp)
      assert all != []
      assert {:ok, unfiltered} = Parser.parse_events_filtered(path, 0, size, @timestamp, %{})
      assert Enum.map(unfiltered, &Map.delete(&1, :byte_offset)) == all
      refute Enum.any?(all, &Map.has_key?(&1, :byte_offset))

      sample = Enum.find(all, &Map.has_key?(&1, :spell_id))

      for filters <- [
            %{event_types: [sample.type]},
            %{source_guids: [sample.source_guid]},
            %{target_guids: [sample.target_guid]},
            %{spell_ids: [sample.spell_id]},
            %{time_min_ms: floor(sample.time_into_fight * 1000)},
            %{time_max_ms: ceil(sample.time_into_fight * 1000)},
            %{
              event_types: [sample.type],
              source_guids: [sample.source_guid],
              spell_ids: [sample.spell_id]
            },
            %{event_types: [], source_guids: [], target_guids: [], spell_ids: []}
          ] do
        expected = Enum.filter(all, &matches?(&1, filters))
        assert {:ok, events} = Parser.parse_events_filtered(path, 0, size, @timestamp, filters)
        assert Enum.map(events, &Map.delete(&1, :byte_offset)) == expected
        assert Enum.map(events, & &1.byte_offset) == Enum.sort(Enum.map(events, & &1.byte_offset))
      end
    end
  end

  test "absolute offsets respect nonzero ranges and CRLF" do
    content = File.read!(@path) |> String.replace("\n", "\r\n")
    path = Path.join(System.tmp_dir!(), "niff-#{System.unique_integer([:positive])}.txt")
    File.write!(path, "ignored\r\n" <> content)
    on_exit(fn -> File.rm!(path) end)

    assert {:ok, events} =
             Parser.parse_events_filtered(path, 9, byte_size(content) + 9, @timestamp, %{})

    assert {:ok, original} = parse(%{})

    assert Enum.map(events, &Map.delete(&1, :byte_offset)) ==
             Enum.map(original, &Map.delete(&1, :byte_offset))

    assert hd(events).byte_offset == hd(original).byte_offset + 10
  end

  test "invalid filter keys and shapes return errors rather than broadening a read" do
    for filters <- [
          %{typo: ["SPELL_DAMAGE"]},
          %{"event_types" => ["SPELL_DAMAGE"]},
          [],
          %{spell_ids: ["89753"]},
          %{event_types: "SPELL_DAMAGE"},
          %{time_min_ms: 3.5},
          %{time_min_ms: 4, time_max_ms: 3}
        ] do
      assert {:error, :invalid_filters} = parse(filters)
    end
  end

  test "lightweight and combatant events never match missing prefix fields" do
    # In the base fixture COMBATANT_INFO has a player GUID, but no target/spell.
    path = Path.expand("../fixtures/combat_log_base.txt", __DIR__)
    size = File.stat!(path).size

    assert {:ok, events} =
             Parser.parse_events_filtered(path, 0, size, @timestamp, %{
               event_types: ["COMBATANT_INFO"]
             })

    assert events != []
    guid = hd(events).source_guid

    assert {:ok, []} =
             Parser.parse_events_filtered(path, 0, size, @timestamp, %{
               event_types: ["COMBATANT_INFO"],
               target_guids: [guid]
             })

    assert {:ok, []} =
             Parser.parse_events_filtered(path, 0, size, @timestamp, %{
               event_types: ["COMBATANT_INFO"],
               spell_ids: [0]
             })
  end

  test "invalid start dates are rejected at the native boundary" do
    for date <- ["13/1/2026", "1/0/2026", "1/1/9223372036854775807", "-2147483648/1/2026"] do
      assert {:error, :bad_start_timestamp} =
               Parser.parse_events_filtered(
                 @path,
                 0,
                 File.stat!(@path).size,
                 date <> " 21:22:10.312-4",
                 %{}
               )
    end
  end

  test "malformed log dates are skipped safely before shared decoding" do
    path =
      Path.join(System.tmp_dir!(), "niff-malformed-#{System.unique_integer([:positive])}.txt")

    content = File.read!(@path)
    malformed = String.replace(content, "8/19/2026", "1/1/9223372036854775807")
    File.write!(path, malformed <> content)
    on_exit(fn -> File.rm!(path) end)

    assert {:ok, events} =
             Parser.parse_events_filtered(
               path,
               0,
               byte_size(malformed <> content),
               @timestamp,
               %{}
             )

    assert {:ok, original} = parse(%{})

    assert Enum.map(events, &Map.delete(&1, :byte_offset)) ==
             Enum.map(original, &Map.delete(&1, :byte_offset))
  end

  test "public build and mode expose the same unavailable filtered parser" do
    source = Path.expand("../../lib/we_go_next/combat_log_parser.ex", __DIR__)

    script = """
    Code.compile_file(#{inspect(source)})
    {:error, :parser_unavailable} = WeGoNext.CombatLogParser.parse_events_filtered("ignored", 0, 1, "ignored", %{})
    IO.puts("public filtered parser PASS")
    """

    for flag <- ["WE_GO_NEXT_BUILD", "WE_GO_NEXT_MODE"] do
      {output, status} =
        System.cmd(System.find_executable("elixir"), ["--erl", "+S 2", "-e", script],
          env: [{flag, "public"}]
        )

      assert status == 0
      assert output =~ "public filtered parser PASS"
    end
  end

  test "invalid ranges and missing files return errors" do
    size = File.stat!(@path).size

    assert {:error, :invalid_byte_range} =
             Parser.parse_events_filtered(@path, 10, 0, @timestamp, %{})

    assert {:error, :invalid_byte_range} =
             Parser.parse_events_filtered(@path, 0, size + 1, @timestamp, %{})

    assert {:ok, []} = Parser.parse_events_filtered(@path, size, size, @timestamp, %{})

    assert {:error, :file_not_found} =
             Parser.parse_events_filtered(@path <> ".missing", 0, 1, @timestamp, %{})
  end

  defp matches?(event, filters) do
    Enum.all?(filters, fn
      {:time_min_ms, value} ->
        event.time_into_fight >= value / 1000

      {:time_max_ms, value} ->
        event.time_into_fight <= value / 1000

      {key, values} ->
        field =
          %{
            event_types: :type,
            source_guids: :source_guid,
            target_guids: :target_guid,
            spell_ids: :spell_id
          }[key]

        values == [] or Map.get(event, field) in values
    end)
  end

  defp parse(filters) do
    Parser.parse_events_filtered(@path, 0, File.stat!(@path).size, @timestamp, filters)
  end
end
