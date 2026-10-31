defmodule WeGoNext.Silver.FeignDeathPersistenceTest do
  use WeGoNext.DataCase, async: false

  alias WeGoNext.Accounts.User
  alias WeGoNext.Analysis.{ReadModel, Session}
  alias WeGoNext.Analysis.Tools.{Deaths, LogEvents}
  alias WeGoNext.CombatLogFile
  alias WeGoNext.CombatLogParser
  alias WeGoNext.Documents
  alias WeGoNext.Encounters.Encounter
  alias WeGoNext.Gold.{DimEncounter, EncounterDetail}
  alias WeGoNext.Repo
  alias WeGoNext.Silver
  alias WeGoNext.Silver.{Death, DeathDerivation}

  @fixture Path.expand("../../fixtures/feign_death_real_pull.txt", __DIR__)
  @start "9/6/2026 11:33:20.939-4"
  @madz "Player-1171-0B076010"

  test "reprojection removes old feigns and stamps even a zero-death partition" do
    dim =
      %DimEncounter{}
      |> DimEncounter.changeset(%{
        wow_encounter_id: "3420",
        name: "Sszorak",
        difficulty_id: 15,
        source_encounter_key: "feign-real-log",
        source_file_path: @fixture,
        start_byte: 0,
        end_byte: File.stat!(@fixture).size,
        fight_time_ms: 200_000,
        start_time: ~U[2026-09-06 15:33:20.939000Z]
      })
      |> Repo.insert!()

    context = analysis_context(dim)

    {:ok, raw} =
      LogEvents.run(
        %{
          "pull" => dim.id,
          "filters" => %{"event_types" => ["UNIT_DIED"], "target_guids" => [@madz]}
        },
        context
      )

    assert Enum.map(raw.data, & &1.unconscious_on_death) == [1, 1, 0]

    {:ok, events} = CombatLogParser.parse_events(@fixture, 0, File.stat!(@fixture).size, @start)
    # Reproduce the old persisted partition by stripping the newly parsed flag.
    old_events = Enum.map(events, &Map.delete(&1, :unconscious_on_death))
    assert {:ok, _} = Silver.project_and_persist(dim, events: old_events)

    dim
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.force_change(:silver_death_derivation_version, nil)
    |> Repo.update!()

    assert Repo.aggregate(Death, :count, :id) == 27

    pulls = [%{pull_id: dim.id, public_encounter_id: 1}]
    log = %{file_size: 0, last_parsed_byte: 0}
    assert ReadModel.freshness(pulls, log).stale_death_pull_ids == [dim.id]

    assert {:ok, stale_document} = Documents.EncounterDocument.encode(dim.id)
    assert Documents.stale?(stale_document)

    assert {:ok, %{counts: %{death: 25}}} = Silver.project_and_persist(dim, events: events)
    assert Repo.aggregate(Death, :count, :id) == 25

    assert Repo.get!(DimEncounter, dim.id).silver_death_derivation_version ==
             DeathDerivation.current_version()

    assert ReadModel.freshness(pulls, log).stale_death_pull_ids == []

    assert {:ok, detail} = EncounterDetail.get(dim.id)
    assert detail.counts.deaths == 25

    assert [%{died_at_ms_into_fight: 171_398}] =
             Enum.filter(detail.deaths, &(&1.target_guid == @madz))

    assert {:ok, document} = Documents.EncounterDocument.encode(dim.id)
    assert document.silver_death_derivation_version == 2
    assert WeGoNext.Freshness.current?(document, :silver_deaths)
    # Silver alone does not prove that either gold output was rebuilt.
    assert Documents.stale?(document)
    assert WeGoNext.Freshness.classify(document).failures == :missing
    assert WeGoNext.Freshness.classify(document).wipe_cause == :missing
    assert length(document.deaths) == 25

    assert {:ok, deaths_result} =
             Deaths.run(%{"pulls" => [dim.id]}, context)

    assert %{target_guid: "Player-1171-0A34A5C5", died_at_ms_into_fight: 155_271} =
             hd(deaths_result.data)

    assert {:ok, %{counts: %{death: 0}}} = Silver.project_and_persist(dim, events: [])
    assert Repo.aggregate(Death, :count, :id) == 0
    assert ReadModel.freshness(pulls, log).stale_death_pull_ids == []
  end

  defp analysis_context(dim) do
    user = Repo.insert!(%User{name: "feign-test"})
    log = Repo.insert!(%CombatLogFile{user_id: user.id, file_path: @fixture})

    Repo.insert!(%Encounter{
      combat_log_file_id: log.id,
      wow_encounter_id: dim.wow_encounter_id,
      name: dim.name,
      start_byte: dim.start_byte,
      start_time: dim.start_time
    })

    Repo.insert!(%Session{
      combat_log_file_id: log.id,
      started_at: dim.start_time
    })
  end
end
