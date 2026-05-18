defmodule WeGoNext.Silver.RoundTripTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias WeGoNext.Analyzers.{
    DamageTakenAnalyzer,
    DeathAnalyzer,
    DebuffAnalyzer,
    InterruptAnalyzer
  }

  alias WeGoNext.Encounter
  alias WeGoNext.Fixtures.CombatLogEventFixtures
  alias WeGoNext.Gold.DimEncounter
  alias WeGoNext.Repo
  alias WeGoNext.Silver

  alias WeGoNext.Silver.{
    DamageTaken,
    DamageTakenEvent,
    Death,
    DebuffApplication,
    InterruptOpportunity,
    PlayerInfo
  }

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    dim_encounter =
      %DimEncounter{}
      |> DimEncounter.changeset(%{
        wow_encounter_id: "round-trip-boss",
        name: "Round Trip Boss",
        difficulty_id: 16,
        difficulty_name: "Mythic",
        group_size: 20,
        instance_id: "round-trip-instance"
      })
      |> Repo.insert!()

    {:ok, dim_encounter: dim_encounter}
  end

  test "silver rows round-trip to legacy analyzer output for core encounter facts", %{
    dim_encounter: dim_encounter
  } do
    events = round_trip_events()
    encounter = encounter_fixture(events)

    damage_taken = DamageTakenAnalyzer.analyze(encounter)
    deaths = DeathAnalyzer.analyze(encounter)
    interrupts = InterruptAnalyzer.analyze(encounter)
    debuffs = DebuffAnalyzer.analyze(encounter)

    assert {:ok, %{counts: counts}} = Silver.project_and_persist(dim_encounter, events: events)

    assert counts == %{
             damage_taken: 2,
             damage_taken_event: 4,
             damage_done: 1,
             death: 1,
             interrupt_opportunity: 2,
             debuff_application: 2,
             player_info: 3
           }

    assert silver_damage_taken_totals(dim_encounter) == legacy_damage_taken_totals(damage_taken)
    assert Repo.aggregate(DamageTakenEvent, :count) == 4
    assert silver_deaths(dim_encounter) == legacy_deaths(deaths)

    assert silver_interrupt_opportunities(dim_encounter) ==
             legacy_interrupt_opportunities(interrupts)

    assert silver_debuff_applications(dim_encounter) == legacy_debuff_applications(debuffs)
    assert silver_tank_guids(dim_encounter) == legacy_tank_guids(damage_taken)
  end

  defp round_trip_events do
    CombatLogEventFixtures.canonical_projection_events()
    |> Enum.map(fn
      %{type: "SPELL_CAST_SUCCESS", spell_id: 888} = event ->
        %{event | spell_id: 777, spell_name: "Scary Cast"}

      %{type: type, extra: extra} = event
      when type in ["SPELL_AURA_APPLIED", "SPELL_AURA_REMOVED"] ->
        %{event | extra: Map.put(extra, "aura_type", "DEBUFF")}

      event ->
        event
    end)
  end

  defp encounter_fixture(events) do
    %Encounter{
      id: "round-trip-boss",
      name: "Round Trip Boss",
      difficulty_id: 16,
      difficulty_name: "Mythic",
      group_size: 20,
      instance_id: "round-trip-instance",
      fight_time_ms: 10_000,
      events: events
    }
  end

  defp silver_damage_taken_totals(dim_encounter) do
    DamageTaken
    |> where([row], row.encounter_dim_id == ^dim_encounter.id)
    |> select([row], {row.target_guid, sum(row.total_amount)})
    |> group_by([row], row.target_guid)
    |> Repo.all()
    |> Map.new(fn {guid, total} -> {guid, Decimal.to_integer(total)} end)
  end

  defp legacy_damage_taken_totals(%{all: players}) do
    players
    |> Enum.map(&{&1.player_guid, &1.total})
    |> Map.new()
  end

  defp silver_deaths(dim_encounter) do
    Death
    |> where([row], row.encounter_dim_id == ^dim_encounter.id)
    |> order_by([row], asc: row.died_at_ms_into_fight)
    |> Repo.all()
    |> Enum.map(fn row ->
      %{
        target_guid: row.target_guid,
        died_at_ms_into_fight: row.died_at_ms_into_fight,
        killing_blow_spell_id: row.killing_blow_spell_id,
        killing_blow_source_guid: row.killing_blow_source_guid,
        recap_amounts: Enum.map(row.damage_recap, & &1["amount"])
      }
    end)
  end

  defp legacy_deaths(deaths) do
    Enum.map(deaths, fn death ->
      %{
        target_guid: death.player_guid,
        died_at_ms_into_fight: round(death.time_into_fight * 1000),
        killing_blow_spell_id: death.killing_blow.ability_id,
        killing_blow_source_guid: "Creature-Boss",
        recap_amounts: Enum.map(death.recap, & &1.amount)
      }
    end)
  end

  defp silver_interrupt_opportunities(dim_encounter) do
    InterruptOpportunity
    |> where([row], row.encounter_dim_id == ^dim_encounter.id)
    |> order_by([row], asc: row.opportunity_ms_into_fight)
    |> Repo.all()
    |> Enum.map(fn row ->
      %{
        interrupted_spell_id: row.interrupted_spell_id,
        opportunity_ms_into_fight: row.opportunity_ms_into_fight,
        success: row.success,
        interrupter_guid: row.interrupter_guid,
        interrupting_spell_id: row.interrupting_spell_id
      }
    end)
  end

  defp legacy_interrupt_opportunities(%{interrupts: interrupts, missed_casts: missed_casts}) do
    success_rows =
      Enum.map(interrupts, fn interrupt ->
        %{
          interrupted_spell_id: interrupt.interrupted_spell_id,
          opportunity_ms_into_fight: round(interrupt.time_into_fight * 1000),
          success: true,
          interrupter_guid: interrupt.interrupter_guid,
          interrupting_spell_id: interrupt.interrupt_spell_id
        }
      end)

    missed_rows =
      Enum.map(missed_casts, fn cast ->
        %{
          interrupted_spell_id: cast.spell_id,
          opportunity_ms_into_fight: round(cast.time_into_fight * 1000),
          success: false,
          interrupter_guid: nil,
          interrupting_spell_id: nil
        }
      end)

    Enum.sort_by(success_rows ++ missed_rows, & &1.opportunity_ms_into_fight)
  end

  defp silver_debuff_applications(dim_encounter) do
    DebuffApplication
    |> where([row], row.encounter_dim_id == ^dim_encounter.id)
    |> order_by([row], asc: row.applied_at_ms_into_fight)
    |> Repo.all()
    |> Enum.map(fn row ->
      %{
        target_guid: row.target_guid,
        source_guid: row.source_guid,
        spell_id: row.spell_id,
        applied_at_ms_into_fight: row.applied_at_ms_into_fight,
        duration_ms: row.duration_ms
      }
    end)
  end

  defp legacy_debuff_applications(%{applications: applications}) do
    applications
    |> Enum.map(fn app ->
      %{
        target_guid: app.player_guid,
        source_guid: app.source_guid,
        spell_id: app.spell_id,
        applied_at_ms_into_fight: round(app.time_into_fight * 1000),
        duration_ms: app.duration && round(app.duration * 1000)
      }
    end)
    |> Enum.sort_by(& &1.applied_at_ms_into_fight)
  end

  defp silver_tank_guids(dim_encounter) do
    PlayerInfo
    |> where([row], row.encounter_dim_id == ^dim_encounter.id and row.detected_role == "tank")
    |> select([row], row.player_guid)
    |> Repo.all()
    |> Enum.sort()
  end

  defp legacy_tank_guids(%{tanks: tanks}) do
    tanks
    |> Enum.map(& &1.player_guid)
    |> Enum.sort()
  end
end
