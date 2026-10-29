defmodule WeGoNext.Silver.PetAttributionRealLogTest do
  use ExUnit.Case, async: true

  alias WeGoNext.CombatLogParser
  alias WeGoNext.Silver.Projector

  @moduledoc """
  Real-log acceptance coverage for pet/guardian damage-done attribution.

  The fixture is a verbatim slice of a local 12.x raid log
  (WoWCombatLog-081926_205942.txt, The Twin Fangs normal pull at 21:22:10).
  It exercises both owner-evidence paths against real advanced-block layouts:

    * Skreetom (felguard, `Pet-` GUID, summoned before the pull) — its
      SWING_DAMAGE advanced block names the owner (Pixen,
      Player-1175-0FF05A1A) while its SPELL_DAMAGE advanced block describes
      the target and carries no owner, so the Felstorm hit must attribute
      through the map learned from the swing.
    * Imp Lord (`Creature-` GUID guardian) — owner known only via the
      SPELL_SUMMON line.
  """

  @fixture_path Path.expand("../../fixtures/pet_attribution_real_pull.txt", __DIR__)
  @encounter_start_timestamp "8/19/2026 21:22:10.312-4"
  @encounter_dim_id 1

  @pixen "Player-1175-0FF05A1A"
  @caedues "Player-1171-0A9F83B7"
  @ithraz "Creature-0-3023-3004-53803-257368-0000065653"

  test "parser surfaces owner_guid only on pet melee hits" do
    events = parsed_fixture()

    assert [pet_swing] = Enum.filter(events, &(&1.type == "SWING_DAMAGE"))
    assert pet_swing.owner_guid == @pixen

    for event <- events, event.type != "SWING_DAMAGE" do
      refute Map.has_key?(event, :owner_guid)
    end
  end

  test "attributes real pet melee, pet spell, and summoned-guardian damage to owners" do
    projection =
      Projector.project(@encounter_dim_id, parsed_fixture())

    assert [caedues_dnd, pixen_melee, pixen_felstorm, pixen_felbolt] = projection.damage_done

    # The player's own damage is untouched by attribution.
    assert %{
             source_guid: @caedues,
             target_guid: @ithraz,
             spell_id: 52_212,
             total_amount: 674
           } = caedues_dnd

    # Felguard melee: owner read directly from the swing advanced block.
    assert %{
             source_guid: @pixen,
             target_guid: @ithraz,
             spell_id: 0,
             total_amount: 2_263
           } = pixen_melee

    # Felguard Felstorm: no owner on the spell line; attributed via the map.
    assert %{
             source_guid: @pixen,
             target_guid: @ithraz,
             spell_id: 89_753,
             total_amount: 1_631
           } = pixen_felstorm

    # Imp Lord (Creature- guardian): attributed via its SPELL_SUMMON line.
    assert %{
             source_guid: @pixen,
             target_guid: @ithraz,
             spell_id: 1_277_116,
             total_amount: 42_664
           } = pixen_felbolt
  end

  defp parsed_fixture do
    {:ok, events} =
      CombatLogParser.parse_events(
        @fixture_path,
        0,
        File.stat!(@fixture_path).size,
        @encounter_start_timestamp
      )

    events
  end
end
