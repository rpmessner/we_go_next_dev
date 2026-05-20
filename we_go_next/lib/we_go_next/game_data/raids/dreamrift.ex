defmodule WeGoNext.GameData.Raids.Dreamrift do
  @moduledoc """
  Curated mechanic catalog for The Dreamrift.
  """

  import WeGoNext.GameData.Raids.CatalogHelpers

  @raid_name "The Dreamrift"
  @raid_slug "the_dreamrift"

  def info do
    %{
      name: @raid_name,
      slug: @raid_slug,
      product: "wow",
      channel: "retail",
      zone_ids: [2939],
      dbm_module_map_ids: [1314],
      tier: "Midnight Season 1"
    }
  end

  def bosses do
    [
      boss("Chimaerus the Undreamt God", 3306, 2795, 1314, 2939)
    ]
  end

  def mechanics do
    [
      %{
        raid_name: @raid_name,
        raid_slug: @raid_slug,
        spell_id: 1_272_726,
        name: "Rending Tear",
        type: :avoidable,
        event: :damage_taken,
        boss_encounter_id: "3306",
        boss_name: "Chimaerus the Undreamt God",
        rule: %{max_hits: 0},
        sources: [:dbm, :local_logs],
        notes: "DBM DodgeCount warning with FRONTAL label and observed damage in current logs."
      },
      %{
        raid_name: @raid_name,
        raid_slug: @raid_slug,
        spell_id: 1_245_406,
        name: "Ravenous Dive",
        type: :avoidable,
        event: :damage_taken,
        boss_encounter_id: "3306",
        boss_name: "Chimaerus the Undreamt God",
        rule: %{max_hits: 0},
        sources: [:wowanalyzer, :local_logs],
        notes:
          "WowAnalyzer labels the cast as Ravenous Dive; observed damage is sparse and should be validated."
      },
      %{
        raid_name: @raid_name,
        raid_slug: @raid_slug,
        spell_id: 1_249_017,
        name: "Fearsome Cry",
        type: :interrupt,
        event: :interrupt_opportunity,
        boss_encounter_id: "3306",
        boss_name: "Chimaerus the Undreamt God",
        rule: %{must_interrupt: true},
        sources: [:dbm],
        track: false,
        notes:
          "DBM interrupt warning. Keep out of automatic rule sync until interrupt silver semantics are tightened."
      },
      %{
        raid_name: @raid_name,
        raid_slug: @raid_slug,
        spell_id: 1_262_289,
        name: "Alndust Upheaval",
        type: :soak,
        event: :cast,
        boss_encounter_id: "3306",
        boss_name: "Chimaerus the Undreamt God",
        sources: [:dbm, :wowanalyzer],
        track: false,
        notes: "Known group soak source annotation; fact semantics are not implemented yet."
      }
    ]
  end

  def rule_criteria, do: rule_criteria(mechanics())
end
