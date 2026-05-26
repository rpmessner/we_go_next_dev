defmodule WeGoNext.Silver.SchemaTest do
  use ExUnit.Case, async: true

  alias WeGoNext.Silver.{
    DamageDone,
    DamageTaken,
    DamageTakenEvent,
    Death,
    DebuffApplication,
    DefensiveBuffWindow,
    InterruptOpportunity,
    PlayerInfo
  }

  test "silver schemas use dedicated schema prefix and clean table names" do
    assert DamageTaken.__schema__(:source) == "damage_taken"
    assert DamageTakenEvent.__schema__(:source) == "damage_taken_event"
    assert DamageDone.__schema__(:source) == "damage_done"
    assert Death.__schema__(:source) == "death"
    assert InterruptOpportunity.__schema__(:source) == "interrupt_opportunity"
    assert DebuffApplication.__schema__(:source) == "debuff_application"
    assert DefensiveBuffWindow.__schema__(:source) == "defensive_buff_window"
    assert PlayerInfo.__schema__(:source) == "player_info"

    assert Enum.all?(
             [
               DamageTaken,
               DamageTakenEvent,
               DamageDone,
               Death,
               InterruptOpportunity,
               DebuffApplication,
               DefensiveBuffWindow,
               PlayerInfo
             ],
             &(&1.__schema__(:prefix) == "silver")
           )
  end

  test "silver changesets accept required fields" do
    assert_changeset_valid(
      DamageTaken.changeset(%DamageTaken{}, %{
        encounter_dim_id: 1,
        target_guid: "Player-1",
        source_guid: "Creature-1",
        spell_id: 123,
        total_amount: 100,
        hit_count: 2,
        max_hit: 75,
        overkill_total: 0,
        source_is_npc: true
      })
    )

    assert_changeset_valid(
      DamageTakenEvent.changeset(%DamageTakenEvent{}, %{
        encounter_dim_id: 1,
        combat_log_event_index: 10,
        event_type: "SPELL_DAMAGE",
        occurred_at_ms_into_fight: 12_345,
        target_guid: "Player-1",
        source_guid: "Creature-1",
        source_is_npc: true,
        spell_id: 123,
        amount: 100,
        overkill: 0
      })
    )

    assert_changeset_valid(
      DamageDone.changeset(%DamageDone{}, %{
        encounter_dim_id: 1,
        source_guid: "Player-1",
        target_guid: "Creature-1",
        spell_id: 123,
        total_amount: 100,
        hit_count: 2,
        max_hit: 75
      })
    )

    assert_changeset_valid(
      Death.changeset(%Death{}, %{
        encounter_dim_id: 1,
        target_guid: "Player-1",
        died_at_ms_into_fight: 12_345,
        damage_recap: [%{"amount" => 100, "spell_id" => 123}]
      })
    )

    assert_changeset_valid(
      InterruptOpportunity.changeset(%InterruptOpportunity{}, %{
        encounter_dim_id: 1,
        target_npc_guid: "Creature-1",
        interrupted_spell_id: 123,
        opportunity_ms_into_fight: 12_345,
        success: false
      })
    )

    assert_changeset_valid(
      DebuffApplication.changeset(%DebuffApplication{}, %{
        encounter_dim_id: 1,
        target_guid: "Player-1",
        source_guid: "Creature-1",
        spell_id: 123,
        applied_at_ms_into_fight: 12_345,
        stack_count: 1
      })
    )

    assert_changeset_valid(
      DefensiveBuffWindow.changeset(%DefensiveBuffWindow{}, %{
        encounter_dim_id: 1,
        target_guid: "Player-1",
        source_guid: "Player-1",
        spell_id: 104_773,
        spell_name: "Unending Resolve",
        category: "personal",
        started_at_ms_into_fight: 12_345
      })
    )

    assert_changeset_valid(
      PlayerInfo.changeset(%PlayerInfo{}, %{
        encounter_dim_id: 1,
        player_guid: "Player-1",
        player_name: "Testplayer",
        detected_role: "unknown"
      })
    )
  end

  test "player info validates detected role" do
    changeset =
      PlayerInfo.changeset(%PlayerInfo{}, %{
        encounter_dim_id: 1,
        player_guid: "Player-1",
        player_name: "Testplayer",
        detected_role: "carry"
      })

    refute changeset.valid?
    assert {"is invalid", _} = Keyword.fetch!(changeset.errors, :detected_role)
  end

  defp assert_changeset_valid(changeset) do
    assert changeset.valid?, inspect(changeset.errors)
  end
end
