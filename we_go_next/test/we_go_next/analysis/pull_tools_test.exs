defmodule WeGoNext.Analysis.PullToolsTest do
  use WeGoNext.DataCase, async: false

  alias WeGoNext.Analysis.Tools.{Deaths, Failures, PullSummary}
  alias WeGoNext.{CombatLogFile, Documents, Repo}
  alias WeGoNext.Encounters.Encounter
  alias WeGoNext.Gold.DimEncounter
  alias WeGoNext.Silver.{Death, PlayerInfo, Projector}

  setup do
    root = Path.join(System.tmp_dir!(), "pull-tools-#{System.unique_integer([:positive])}")
    original = Application.fetch_env!(:we_go_next, :documents_root)
    Application.put_env(:we_go_next, :documents_root, root)

    on_exit(fn ->
      Application.put_env(:we_go_next, :documents_root, original)
      File.rm_rf!(root)
    end)

    user = Repo.insert!(%WeGoNext.Accounts.User{name: "pull-tools"})
    log = Repo.insert!(%CombatLogFile{user_id: user.id, file_path: "/real-slice.txt"})

    dim =
      Repo.insert!(%DimEncounter{
        source_file_path: log.file_path,
        source_encounter_key: "real-slice",
        name: "Lightblinded Vanguard",
        wow_encounter_id: "3180",
        start_byte: 0,
        start_time: ~U[2026-07-19 15:38:36.049000Z],
        difficulty_id: 16,
        fight_time_ms: 300_000,
        success: false
      })

    Repo.insert!(%Encounter{
      combat_log_file_id: log.id,
      name: dim.name,
      wow_encounter_id: dim.wow_encounter_id,
      start_byte: 0,
      start_time: dim.start_time,
      fight_time_ms: dim.fight_time_ms,
      success: false
    })

    path = Path.expand("../../fixtures/survival_actions_real_pull.txt", __DIR__)

    assert {:ok, events} =
             WeGoNext.CombatLogParser.parse_events(
               path,
               0,
               File.stat!(path).size,
               "7/19/2026 11:38:36.049-4"
             )

    projection = Projector.project(dim.id, events)
    for row <- projection.player_info, do: Repo.insert!(PlayerInfo.changeset(%PlayerInfo{}, row))
    for row <- projection.death, do: Repo.insert!(Death.changeset(%Death{}, row))

    for row <- projection.damage_taken,
        do:
          Repo.insert!(WeGoNext.Silver.DamageTaken.changeset(%WeGoNext.Silver.DamageTaken{}, row))

    ruleset =
      Repo.insert!(
        WeGoNext.Rules.Ruleset.changeset(%WeGoNext.Rules.Ruleset{}, %{
          name: "Fixture rules",
          status: "active"
        })
      )

    Repo.insert!(
      WeGoNext.Gold.DimMechanicCriterion.changeset(%WeGoNext.Gold.DimMechanicCriterion{}, %{
        source_rule_id: 1,
        ruleset_id: ruleset.id,
        ruleset_version: ruleset.version,
        spell_id: 1_246_502,
        spell_name: "Avenger's Shield",
        mechanic_type: "avoidable",
        boss_encounter_id: dim.wow_encounter_id,
        difficulty_id: 16,
        threshold: %{"max_hits" => 0}
      })
    )

    assert {:ok, %{inserted: 1}} = WeGoNext.Gold.FactFailure.rebuild_for_encounter(dim.id)
    {:ok, context: %{id: Ecto.UUID.generate(), combat_log_file_id: log.id}, dim: dim}
  end

  test "deaths reads the real death, killing blow and recap from silver", %{
    context: context,
    dim: dim
  } do
    assert {:ok, page} = Deaths.run(%{"pulls" => [dim.id]}, context)
    assert [first | _] = page.data
    assert first.player_name == "Manaken"
    assert first.died_at_ms_into_fight == 147_028
    assert first.killing_blow["spell_id"] == 1_246_502
    assert first.damage_recap != []
    assert first.recap_count == 5
    assert Enum.all?(page.evidence, &(&1.pull_id == dim.id and &1.ms_into_fight == 147_028))
    assert byte_size(Jason.encode!(page)) <= 8192
  end

  test "failures returns gold facts with optional exact player and mechanic filters", %{
    context: context,
    dim: dim
  } do
    args = %{"pulls" => [dim.id], "player" => "Manaken", "mechanic" => "1246502"}
    assert {:ok, page} = Failures.run(args, context)

    assert [
             %{
               pull_id: id,
               player_name: "Manaken",
               spell_id: 1_246_502,
               failure_count: 2,
               total_damage: 186_438
             }
           ] = page.data

    assert id == dim.id
    assert [%{pull_id: ^id, timestamp: timestamp, source: "gold.fact_failure"}] = page.evidence
    assert timestamp == dim.start_time
    assert {:ok, %{data: []}} = Failures.run(Map.put(args, "player", "Other"), context)
    assert {:ok, %{data: []}} = Failures.run(Map.put(args, "mechanic", "Other"), context)
  end

  test "schemas accept agent args and reject malformed pull selectors", %{
    context: context,
    dim: dim
  } do
    alias WeGoNext.Analysis.Arguments

    for {tool, selector} <- [
          {PullSummary, %{"pull" => dim.id}},
          {Deaths, %{"pulls" => [dim.id]}},
          {Failures,
           %{"pulls" => [dim.id], "player" => "Manaken", "mechanic" => "Avenger's Shield"}}
        ] do
      args = Map.put(selector, "session_id", context.id)
      assert :ok = Arguments.validate(args, tool.input_schema())
      assert {:error, _} = Arguments.validate(%{"session_id" => context.id}, tool.input_schema())
      assert {:error, _} = Arguments.validate(Map.put(args, "unknown", true), tool.input_schema())
    end

    for bad <- [[], [0], ["1"], [nil]] do
      assert {:error, _} =
               Arguments.validate(
                 %{"session_id" => context.id, "pulls" => bad},
                 Deaths.input_schema()
               )
    end
  end

  test "all primitives reject pulls outside the session log rather than returning partial data",
       %{context: context, dim: dim} do
    other =
      Repo.insert!(%DimEncounter{
        source_file_path: "/other.txt",
        name: "Other",
        wow_encounter_id: "1",
        start_byte: 0
      })

    for {tool, args} <- [
          {PullSummary, %{"pull" => other.id}},
          {Deaths, %{"pulls" => [dim.id, other.id]}},
          {Failures, %{"pulls" => [other.id]}}
        ] do
      assert {:error, "Pull not found in this Analysis session log"} = tool.run(args, context)
    end

    assert {:error, reason} = PullSummary.run(%{"pull" => dim.id}, context)
    assert reason =~ "document unavailable"
  end

  test "death recap pagination is lossless even when one death exceeds the cap", %{
    context: context,
    dim: dim
  } do
    death = Repo.one!(Death)
    recap = for n <- 1..200, do: Map.put(hd(death.damage_recap), "amount", n)
    Repo.update!(Ecto.Changeset.change(death, damage_recap: recap))
    args = %{"pulls" => [dim.id]}
    assert {:ok, page} = Deaths.run(args, context)
    assert page.truncated
    rows = drain(Deaths, args, context, page)
    assert Enum.flat_map(rows, & &1.damage_recap) == recap
    assert Enum.map(rows, & &1.recap_index) == Enum.to_list(0..199)
    assert {:error, _} = Deaths.run(Map.put(args, "cursor", "invalid"), context)
  end

  test "summary and failure cursors cover an expanded real-fixture roster", %{
    context: context,
    dim: dim
  } do
    player =
      Repo.get_by!(PlayerInfo, encounter_dim_id: dim.id, player_guid: "Player-1171-09045C8D")

    fact = Repo.one!(WeGoNext.Gold.FactFailure)

    for n <- 1..80 do
      guid = "Player-expanded-#{n}"

      Repo.insert!(%PlayerInfo{
        encounter_dim_id: dim.id,
        player_guid: guid,
        player_name: "Fixture player #{n}",
        class_id: player.class_id,
        spec_id: player.spec_id,
        detected_role: player.detected_role
      })

      gold =
        Repo.insert!(%WeGoNext.Gold.DimPlayer{
          player_guid: guid,
          player_name: "Fixture player #{n}"
        })

      Repo.insert!(%WeGoNext.Gold.FactFailure{
        encounter_dim_id: dim.id,
        player_dim_id: gold.id,
        criterion_dim_id: fact.criterion_dim_id,
        ruleset_id: fact.ruleset_id,
        ruleset_version: fact.ruleset_version,
        failure_count: fact.failure_count,
        total_damage: fact.total_damage,
        derivation_version: fact.derivation_version
      })
    end

    assert {:ok, _} = Documents.generate_for_encounter(dim.id)

    for {tool, args, count} <- [
          {PullSummary, %{"pull" => dim.id}, 92},
          {Failures, %{"pulls" => [dim.id]}, 81}
        ] do
      assert {:ok, page} = tool.run(args, context)
      assert page.truncated
      assert length(drain(tool, args, context, page)) == count
      assert {:error, _} = tool.run(Map.put(args, "cursor", "invalid"), context)
    end
  end

  test "registered primitives execute and audit through the read-only executor", %{
    context: context,
    dim: dim
  } do
    assert {:ok, _} = Documents.generate_for_encounter(dim.id)

    assert {:ok, session} =
             WeGoNext.Analysis.start_session(%{"log" => to_string(context.combat_log_file_id)})

    for {tool, selector} <- [
          {PullSummary, %{"pull" => dim.id}},
          {Deaths, %{"pulls" => [dim.id]}},
          {Failures, %{"pulls" => [dim.id]}}
        ] do
      assert {:ok, page} =
               WeGoNext.Analysis.call_tool(
                 tool.name(),
                 Map.put(selector, "session_id", session.id)
               )

      assert page.data != []
      call = Repo.get_by!(WeGoNext.Analysis.ToolCall, session_id: session.id, tool: tool.name())
      assert call.error == nil
      assert call.result_size <= 8192
      assert call.result == Jason.decode!(Jason.encode!(page))
    end

    assert Repo.aggregate(Death, :count) == 1
    assert Repo.aggregate(WeGoNext.Gold.FactFailure, :count) == 1
  end

  test "deaths with no stored recap remain visible", %{context: context, dim: dim} do
    death = Repo.one!(Death)

    Repo.update!(
      Ecto.Changeset.change(death,
        damage_recap: [],
        killing_blow_spell_id: nil,
        killing_blow_source_guid: nil
      )
    )

    assert {:ok, page} = Deaths.run(%{"pulls" => [dim.id]}, context)
    assert [%{damage_recap: [], killing_blow: nil, recap_count: 0, recap_index: nil}] = page.data
    assert [%{ms_into_fight: 147_028}] = page.evidence
  end

  test "failure facts retain the pull grain across pulls and duplicate selectors", %{
    context: context,
    dim: dim
  } do
    second =
      Repo.insert!(%DimEncounter{
        source_file_path: dim.source_file_path,
        source_encounter_key: "second-real-slice",
        name: dim.name,
        wow_encounter_id: dim.wow_encounter_id,
        start_byte: 100,
        start_time: DateTime.add(dim.start_time, 600),
        difficulty_id: 16
      })

    Repo.insert!(%Encounter{
      combat_log_file_id: context.combat_log_file_id,
      name: second.name,
      wow_encounter_id: second.wow_encounter_id,
      start_byte: 100,
      start_time: second.start_time
    })

    fact = Repo.one!(WeGoNext.Gold.FactFailure)

    Repo.insert!(%WeGoNext.Gold.FactFailure{
      encounter_dim_id: second.id,
      player_dim_id: fact.player_dim_id,
      criterion_dim_id: fact.criterion_dim_id,
      ruleset_id: fact.ruleset_id,
      ruleset_version: fact.ruleset_version,
      failure_count: 1,
      total_damage: 100,
      derivation_version: fact.derivation_version
    })

    assert {:ok, page} = Failures.run(%{"pulls" => [second.id, dim.id, dim.id]}, context)
    assert Enum.map(page.data, &{&1.pull_id, &1.failure_count}) == [{dim.id, 2}, {second.id, 1}]
    assert Enum.map(page.evidence, & &1.timestamp) == [dim.start_time, second.start_time]

    assert {:ok, by_guid} =
             Failures.run(
               %{
                 "pulls" => [dim.id],
                 "player" => "Player-1171-09045C8D",
                 "mechanic" => "Avenger's Shield"
               },
               context
             )

    assert [%{failure_count: 2}] = by_guid.data
  end

  defp drain(tool, args, context, page) do
    assert byte_size(Jason.encode!(page)) <= 8192

    if page.truncated do
      assert is_binary(page.next_cursor)
      assert {:ok, next} = tool.run(Map.put(args, "cursor", page.next_cursor), context)
      page.data ++ drain(tool, args, context, next)
    else
      assert page.next_cursor == nil
      page.data
    end
  end

  test "pull_summary reads the stored overview, roster and signals", %{context: context, dim: dim} do
    assert {:ok, _} = Documents.generate_for_encounter(dim.id)
    Repo.delete_all(Death)
    Repo.delete_all(WeGoNext.Gold.FactFailure)
    assert {:ok, %{data: []}} = Deaths.run(%{"pulls" => [dim.id]}, context)
    assert {:ok, page} = PullSummary.run(%{"pull" => dim.id}, context)

    assert Enum.any?(
             page.data,
             &(&1.section == "overview" and &1.value.encounter.name == "Lightblinded Vanguard")
           )

    assert Enum.any?(page.data, &(&1.section == "roster" and &1.value.player_name == "Manaken"))

    assert Enum.any?(
             page.data,
             &(&1.section == "pull_signals" and &1.value.deaths == 1 and
                 &1.value.tracked_failures.failures == 2)
           )

    assert Enum.all?(page.evidence, &(&1.pull_id == dim.id and &1.timestamp == dim.start_time))
    assert byte_size(Jason.encode!(page)) <= 8192
  end
end
