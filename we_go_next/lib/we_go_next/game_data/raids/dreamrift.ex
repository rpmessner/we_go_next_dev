defmodule WeGoNext.GameData.Raids.Dreamrift do
  @moduledoc """
  Curated mechanic catalog for The Dreamrift.
  """

  import WeGoNext.GameData.Raids.CatalogHelpers, only: [boss: 5, rule_criteria: 1]
  alias WeGoNext.GameData.Raids.CatalogHelpers

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
      mechanic(
        "Chimaerus the Undreamt God",
        3306,
        1_245_406,
        "Ravenous Dive",
        :avoidable,
        :damage_taken,
        [:wowanalyzer, :local_logs],
        track: true,
        rule: %{max_hits: 0},
        notes:
          "WowAnalyzer labels the cast as Ravenous Dive; observed damage is sparse and should be validated."
      ),
      mechanic(
        "Chimaerus the Undreamt God",
        3306,
        1_245_452,
        "Corrupted Devastation",
        :avoidable,
        :damage_taken,
        [:dbm]
      ),
      mechanic(
        "Chimaerus the Undreamt God",
        3306,
        1_272_726,
        "Rending Tear",
        :avoidable,
        :damage_taken,
        [:dbm, :local_logs],
        track: true,
        rule: %{max_hits: 0},
        notes: "DBM DodgeCount warning with FRONTAL label and observed damage in current logs."
      ),
      mechanic(
        "Chimaerus the Undreamt God",
        3306,
        1_249_017,
        "Fearsome Cry",
        :interrupt,
        :interrupt_opportunity,
        [:dbm],
        notes:
          "DBM interrupt warning. Keep out of automatic rule sync until interrupt silver semantics are tightened."
      ),
      mechanic("Chimaerus the Undreamt God", 3306, 1_246_149, "Alndust Upheaval", :soak, :cast, [
        :wowanalyzer
      ]),
      mechanic(
        "Chimaerus the Undreamt God",
        3306,
        1_262_289,
        "Alndust Upheaval",
        :soak,
        :cast,
        [:dbm, :wowanalyzer],
        notes: "Known group soak source annotation; fact semantics are not implemented yet."
      ),
      mechanic(
        "Chimaerus the Undreamt God",
        3306,
        1_257_087,
        "Consuming Miasma",
        :healer_mechanic,
        :debuff_application,
        [:wowanalyzer]
      ),
      mechanic("Chimaerus the Undreamt God", 3306, 1_245_396, "Consume", :unknown, :cast, [
        :dbm,
        :wowanalyzer
      ]),
      mechanic(
        "Chimaerus the Undreamt God",
        3306,
        1_273_112,
        "Consume",
        :unknown,
        :damage_taken,
        [:local_logs],
        notes: "Observed damage outcome for Consume; no supported attribution semantics yet."
      ),
      mechanic("Chimaerus the Undreamt God", 3306, 1_245_404, "Ravenous Dive", :unknown, :cast, [
        :dbm
      ]),
      mechanic(
        "Chimaerus the Undreamt God",
        3306,
        1_245_451,
        "Discordant Roar",
        :unknown,
        :cast,
        [:dbm]
      ),
      mechanic(
        "Chimaerus the Undreamt God",
        3306,
        1_245_844,
        "Cannibalized",
        :unknown,
        :debuff_application,
        [:dbm]
      ),
      mechanic("Chimaerus the Undreamt God", 3306, 1_246_621, "Caustic Phlegm", :unknown, :cast, [
        :dbm
      ]),
      mechanic(
        "Chimaerus the Undreamt God",
        3306,
        1_246_653,
        "Caustic Phlegm",
        :unknown,
        :damage_taken,
        [:dbm, :local_logs],
        notes:
          "High-volume observed damage for DBM AOEDAMAGE cast 1246621; do not treat as generic avoidable damage."
      ),
      mechanic("Chimaerus the Undreamt God", 3306, 1_251_021, "Rift Emergence", :unknown, :cast, [
        :dbm
      ]),
      mechanic("Chimaerus the Undreamt God", 3306, 1_258_610, "Rift Emergence", :unknown, :cast, [
        :wowanalyzer
      ]),
      mechanic("Chimaerus the Undreamt God", 3306, 1_264_756, "Rift Madness", :unknown, :cast, [
        :wowanalyzer
      ]),
      mechanic("Chimaerus the Undreamt God", 3306, 1_264_757, "Rift Madness", :unknown, :cast, [
        :wowanalyzer
      ]),
      mechanic(
        "Chimaerus the Undreamt God",
        3306,
        1_280_655,
        "Cannibalized Essence",
        :unknown,
        :damage_taken,
        [:local_logs],
        notes:
          "Observed damage without source warning evidence; attribution semantics need review."
      ),
      mechanic(
        "Chimaerus the Undreamt God",
        3306,
        1_258_192,
        "Lingering Miasma",
        :unknown,
        :damage_taken,
        [:local_logs],
        notes: "Observed damage/debuff spell; not currently failure-eligible."
      )
    ]
  end

  def rule_criteria, do: rule_criteria(mechanics())

  defp mechanic(boss_name, encounter_id, spell_id, name, type, event, sources, opts \\ []) do
    CatalogHelpers.mechanic(
      @raid_name,
      @raid_slug,
      boss_name,
      encounter_id,
      spell_id,
      name,
      type,
      event,
      sources,
      opts
    )
  end
end
