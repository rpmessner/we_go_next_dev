defmodule WeGoNext.Analysis.ToolsTest do
  use WeGoNext.DataCase, async: false

  alias WeGoNext.Analysis.Tools.{ListPulls, SessionContext}
  alias WeGoNext.{CombatLogFile, Repo}
  alias WeGoNext.Encounters.Encounter
  alias WeGoNext.Gold.DimEncounter
  alias WeGoNext.Silver.PlayerInfo

  setup do
    user = Repo.insert!(%WeGoNext.Accounts.User{name: "analysis-tools"})

    log =
      Repo.insert!(%CombatLogFile{
        user_id: user.id,
        file_path: "/fixture.txt",
        last_parsed_at: ~U[2026-09-06 12:00:00Z]
      })

    other = Repo.insert!(%CombatLogFile{user_id: user.id, file_path: "/other.txt"})

    pull =
      Repo.insert!(%Encounter{
        combat_log_file_id: log.id,
        name: "Sszorak",
        wow_encounter_id: "1",
        start_byte: 10,
        start_time: ~U[2026-09-06 12:00:00.000000Z],
        fight_time_ms: 120_000,
        success: false
      })

    dim =
      Repo.insert!(%DimEncounter{
        source_file_path: log.file_path,
        name: "Sszorak",
        wow_encounter_id: "1",
        start_byte: 10
      })

    Repo.insert!(%Encounter{
      combat_log_file_id: other.id,
      name: "Other boss",
      wow_encounter_id: "2",
      start_time: ~U[2026-09-06 12:00:00.000000Z]
    })

    Repo.insert!(%PlayerInfo{
      encounter_dim_id: dim.id,
      player_guid: "Player-1",
      player_name: "Mittwoch",
      class_id: 9,
      spec_id: 266,
      detected_role: "dps"
    })

    {:ok, context: %{id: Ecto.UUID.generate(), combat_log_file_id: log.id}, pull: pull, dim: dim}
  end

  test "Tools read a real-log fixture slice projected into the warehouse", %{context: context} do
    path = Path.expand("../../fixtures/pet_attribution_real_pull.txt", __DIR__)
    boss = "The Twin Fangs"

    Repo.insert!(%Encounter{
      combat_log_file_id: context.combat_log_file_id,
      name: boss,
      wow_encounter_id: "3421",
      start_byte: 1_000,
      start_time: ~U[2026-08-20 01:22:10.312000Z]
    })

    dim =
      Repo.insert!(%DimEncounter{
        source_file_path: "/fixture.txt",
        name: boss,
        wow_encounter_id: "3421",
        start_byte: 1_000
      })

    assert {:ok, events} =
             WeGoNext.CombatLogParser.parse_events(
               path,
               0,
               File.stat!(path).size,
               "8/19/2026 21:22:10.312-4"
             )

    projection = WeGoNext.Silver.Projector.project(dim.id, events)

    for attrs <- projection.player_info do
      Repo.insert!(PlayerInfo.changeset(%PlayerInfo{}, attrs))
    end

    assert {:ok, result} = ListPulls.run(%{"boss" => "The Twin Fangs"}, context)
    assert [%{boss: "The Twin Fangs", pull_id: id}] = result.data
    assert id == dim.id
    assert {:ok, snapshot} = SessionContext.run(%{}, context)
    assert Enum.any?(snapshot.data.pulls, &(&1.pull_id == dim.id))

    assert Enum.any?(
             snapshot.data.roster,
             &(&1.name == "Pixen" and &1.guid == "Player-1175-0FF05A1A")
           )
  end

  test "list_pulls returns scoped pulls and gold evidence", %{
    context: context,
    pull: pull,
    dim: dim
  } do
    assert {:ok, result} = ListPulls.run(%{"night" => "2026-09-06"}, context)

    assert [
             %{
               boss: "Sszorak",
               number: 1,
               outcome: "wipe",
               duration_ms: 120_000,
               public_encounter_id: public_id,
               pull_id: gold_id
             }
           ] = result.data

    assert public_id == pull.id
    assert gold_id == dim.id

    assert [%{pull_id: ^gold_id, source: "public.encounters + gold.dim_encounter", timestamp: _}] =
             result.evidence

    refute result.truncated
    assert result.next_cursor == nil
  end

  test "snapshot reports stale fact stamps and missing medallion pulls", %{
    context: context,
    dim: dim
  } do
    player =
      Repo.insert!(%WeGoNext.Gold.DimPlayer{player_guid: "Player-stale", player_name: "Stale"})

    criterion =
      Repo.insert!(%WeGoNext.Gold.DimMechanicCriterion{
        criterion_key: "analysis-test",
        spell_id: 1,
        spell_name: "Test",
        mechanic_type: "avoidable"
      })

    Repo.insert!(%WeGoNext.Gold.FactFailure{
      encounter_dim_id: dim.id,
      player_dim_id: player.id,
      criterion_dim_id: criterion.id,
      failure_count: 1,
      derivation_version: 1
    })

    missing =
      Repo.insert!(%Encounter{
        combat_log_file_id: context.combat_log_file_id,
        name: "Missing",
        wow_encounter_id: "3",
        start_byte: 500,
        start_time: ~U[2026-09-06 13:00:00.000000Z]
      })

    assert {:ok, result} = SessionContext.run(%{}, context)
    assert result.data.freshness.stale_failure_pull_ids == [dim.id]
    assert result.data.freshness.unimported_pull_ids == [missing.id]
    assert result.data.freshness.stale_failure_pull_count == 1
    assert result.data.freshness.unimported_pull_count == 1
  end

  test "snapshot pagination covers a large log including missing medallion pulls", %{
    context: context
  } do
    for n <- 1..600 do
      Repo.insert!(%Encounter{
        combat_log_file_id: context.combat_log_file_id,
        name: "Sszorak",
        wow_encounter_id: "1",
        start_byte: n + 100,
        start_time: DateTime.add(~U[2026-09-06 12:00:00.000000Z], n, :second)
      })
    end

    assert {:ok, page} = SessionContext.run(%{}, context)
    assert page.truncated
    assert byte_size(Jason.encode!(page)) <= 3_072
    {pulls, roster} = drain_snapshot(context, page, page.data.pulls, page.data.roster)
    assert length(pulls) == 601
    assert [%{name: "Mittwoch"}] = Enum.map(roster, &Map.take(&1, [:name]))
  end

  defp drain_snapshot(_context, %{truncated: false}, pulls, roster), do: {pulls, roster}

  defp drain_snapshot(context, page, pulls, roster) do
    assert {:ok, next} = SessionContext.run(%{"cursor" => page.next_cursor}, context)
    assert byte_size(Jason.encode!(next)) <= 3_072
    drain_snapshot(context, next, pulls ++ next.data.pulls, roster ++ next.data.roster)
  end

  test "session_context includes real roster and freshness within the log", %{context: context} do
    assert {:ok, result} = SessionContext.run(%{}, context)
    assert [%{name: "Mittwoch", class_id: 9, spec_id: 266, role: "dps"}] = result.data.roster
    assert [%{boss: "Sszorak"}] = Enum.map(result.data.pulls, &Map.take(&1, [:boss]))
    assert result.data.freshness.unimported_pull_ids == []
    assert result.data.freshness.current_failure_derivation == 3

    assert Enum.any?(
             result.evidence,
             &match?(%{source: "silver.player_info + gold.dim_encounter", timestamp: _}, &1)
           )
  end
end
