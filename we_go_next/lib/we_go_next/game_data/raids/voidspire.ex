defmodule WeGoNext.GameData.Raids.Voidspire do
  @moduledoc """
  Curated mechanic catalog for The Voidspire.

  DBM, WowAnalyzer, journal data, and local log observations are scaffolding
  inputs, but this file is the curated source used to seed editable rules.
  """

  import WeGoNext.GameData.Raids.CatalogHelpers

  @raid_name "The Voidspire"
  @raid_slug "the_voidspire"

  def info do
    %{
      name: @raid_name,
      slug: @raid_slug,
      product: "wow",
      channel: "retail",
      zone_ids: [2912],
      dbm_module_map_ids: [1307],
      tier: "Midnight Season 1"
    }
  end

  def bosses do
    [
      boss("Imperator Averzian", 3176, 2733, 1307, 2912),
      boss("Vorasius", 3177, 2734, 1307, 2912),
      boss("Vaelgor & Ezzorak", 3178, 2735, 1307, 2912),
      boss("Fallen King Salhadaar", 3179, 2736, 1307, 2912),
      boss("Lightblinded Vanguard", 3180, 2737, 1307, 2912),
      boss("Crown of the Cosmos", 3181, 2738, 1307, 2912)
    ]
  end

  def mechanics do
    [
      %{
        raid_name: @raid_name,
        raid_slug: @raid_slug,
        spell_id: 1_246_765,
        name: "Divine Storm",
        type: :avoidable,
        event: :damage_taken,
        boss_encounter_id: "3180",
        boss_name: "Lightblinded Vanguard",
        rule: %{max_hits: 0},
        sources: [:dbm, :local_logs],
        notes:
          "DBM marks this as a melee movement warning; observed as player damage in current logs."
      },
      %{
        raid_name: @raid_name,
        raid_slug: @raid_slug,
        spell_id: 1_248_652,
        name: "Divine Toll",
        type: :avoidable,
        event: :damage_taken,
        boss_encounter_id: "3180",
        boss_name: "Lightblinded Vanguard",
        rule: %{max_hits: 0},
        sources: [:dbm, :local_logs],
        notes: "DBM DodgeCount warning with DODGES label and observed damage in current logs."
      },
      %{
        raid_name: @raid_name,
        raid_slug: @raid_slug,
        spell_id: 1_243_753,
        name: "Ravenous Abyss",
        type: :avoidable,
        event: :damage_taken,
        boss_encounter_id: "3181",
        boss_name: "Crown of the Cosmos",
        rule: %{max_hits: 0},
        sources: [:dbm, :wowanalyzer, :local_logs],
        notes: "DBM DodgeCount warning; WowAnalyzer identifies the cast as Ravenous Abyss."
      }
    ]
  end

  def rule_criteria, do: rule_criteria(mechanics())
end
