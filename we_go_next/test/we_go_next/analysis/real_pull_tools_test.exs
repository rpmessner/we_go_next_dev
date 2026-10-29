defmodule WeGoNext.Analysis.RealPullToolsTest do
  @moduledoc "Opt-in largest-pull check: set WGN_ANALYSIS_REAL_LOG to a real combat log."
  use WeGoNext.DataCase, async: false

  if path = System.get_env("WGN_ANALYSIS_REAL_LOG") do
    alias WeGoNext.Analysis.Tools.{Deaths, Failures, PullSummary}
    alias WeGoNext.{CombatLogFile, CombatLogParser, Documents, Repo, Rules, Silver}
    alias WeGoNext.Encounters.Encounter
    alias WeGoNext.Gold.{DimEncounter, FactFailure}
    @path path
    @tag timeout: 180_000
    test "all three primitives paginate the largest real pull without losing rows" do
      assert {:ok, boundaries, _} = CombatLogParser.scan_boundaries(@path, 0)

      boundary =
        boundaries
        |> Enum.filter(&Map.has_key?(&1, :wow_encounter_id))
        |> Enum.max_by(&(&1.end_byte - &1.start_byte))

      assert {:ok, events} =
               CombatLogParser.parse_events(
                 @path,
                 boundary.start_byte,
                 boundary.end_byte,
                 boundary.start_timestamp
               )

      user = Repo.insert!(%WeGoNext.Accounts.User{name: "largest-real-pull"})
      log = Repo.insert!(%CombatLogFile{user_id: user.id, file_path: @path})
      start_time = timestamp(boundary.start_timestamp)

      dim =
        Repo.insert!(%DimEncounter{
          source_file_path: @path,
          source_encounter_key: "largest-real-pull",
          start_byte: boundary.start_byte,
          end_byte: boundary.end_byte,
          name: boundary.name,
          wow_encounter_id: to_string(boundary.wow_encounter_id),
          difficulty_id: boundary.difficulty_id,
          start_time: start_time,
          fight_time_ms: boundary.fight_time_ms,
          success: boundary.success
        })

      Repo.insert!(%Encounter{
        combat_log_file_id: log.id,
        start_byte: dim.start_byte,
        start_time: start_time,
        name: dim.name,
        wow_encounter_id: dim.wow_encounter_id,
        fight_time_ms: dim.fight_time_ms,
        success: dim.success
      })

      assert {:ok, persisted} = Silver.project_and_persist(dim, events: events)
      assert {:ok, _} = Rules.sync_current_tier_rules(activate: true)
      # An explicit test-only criterion exercises fact reads even when the current
      # tier catalog no longer covers the historical log's boss/spells.
      ruleset = Repo.get_by!(WeGoNext.Rules.Ruleset, status: "active")
      sample = Enum.max_by(persisted.projection.damage_taken, & &1.hit_count)

      Repo.insert!(
        WeGoNext.Gold.DimMechanicCriterion.changeset(%WeGoNext.Gold.DimMechanicCriterion{}, %{
          source_rule_id: 9_999_999,
          ruleset_id: ruleset.id,
          ruleset_version: ruleset.version,
          spell_id: sample.spell_id,
          spell_name: "Real-pull test criterion",
          mechanic_type: "avoidable",
          boss_encounter_id: dim.wow_encounter_id,
          difficulty_id: dim.difficulty_id,
          threshold: %{"max_hits" => 0}
        })
      )

      assert {:ok, rebuilt} = FactFailure.rebuild_for_encounter(dim.id)
      original = Application.fetch_env!(:we_go_next, :documents_root)

      root =
        Path.join(System.tmp_dir!(), "largest-real-tools-#{System.unique_integer([:positive])}")

      Application.put_env(:we_go_next, :documents_root, root)

      on_exit(fn ->
        Application.put_env(:we_go_next, :documents_root, original)
        File.rm_rf!(root)
      end)

      assert {:ok, _} = Documents.generate_for_encounter(dim.id)
      context = %{id: Ecto.UUID.generate(), combat_log_file_id: log.id}
      summary = pages(PullSummary, %{"pull" => dim.id}, context)
      deaths = pages(Deaths, %{"pulls" => [dim.id]}, context)
      failures = pages(Failures, %{"pulls" => [dim.id]}, context)

      assert Enum.count(summary, &(&1.section == "roster")) ==
               length(persisted.projection.player_info)

      assert length(Enum.uniq_by(deaths, & &1.death_id)) == length(persisted.projection.death)

      assert Enum.flat_map(deaths, & &1.damage_recap) |> length() ==
               Enum.sum(Enum.map(persisted.projection.death, &length(&1.damage_recap)))

      assert length(failures) == rebuilt.inserted
      assert deaths != []
      assert failures != []

      IO.puts(
        "REAL_PULL #{dim.name}: bytes=#{boundary.end_byte - boundary.start_byte}, events=#{length(events)}, deaths=#{length(persisted.projection.death)}, recap_rows=#{length(deaths)}, failure_rows=#{length(failures)}, summary_rows=#{length(summary)}"
      )
    end

    defp pages(tool, args, context) do
      {elapsed_us, result} = :timer.tc(tool, :run, [args, context])
      assert {:ok, page} = result
      assert elapsed_us < 5_000_000
      assert byte_size(Jason.encode!(page)) <= 8192
      assert Enum.all?(page.evidence, &(&1.pull_id != nil and &1.timestamp != nil))

      IO.puts(
        "#{tool.name()} page: bytes=#{byte_size(Jason.encode!(page))}, rows=#{length(page.data)}, truncated=#{page.truncated}, ms=#{div(elapsed_us, 1000)}"
      )

      if page.truncated do
        assert is_binary(page.next_cursor)
        page.data ++ pages(tool, Map.put(args, "cursor", page.next_cursor), context)
      else
        assert page.next_cursor == nil
        page.data
      end
    end

    defp timestamp(value) do
      [_, month, day, year, time, sign, hours] =
        Regex.run(~r/^(\d+)\/(\d+)\/(\d+) (\d+:\d+:\d+\.\d+)([+-])(\d+)$/, value)

      {:ok, dt, _} =
        DateTime.from_iso8601(
          "#{year}-#{String.pad_leading(month, 2, "0")}-#{String.pad_leading(day, 2, "0")}T#{time}#{sign}#{String.pad_leading(hours, 2, "0")}:00"
        )

      %{dt | microsecond: {elem(dt.microsecond, 0), 6}}
    end
  end
end
