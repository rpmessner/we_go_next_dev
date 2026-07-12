defmodule WeGoNext.GameData.Raids.CatalogHelpers do
  @moduledoc false

  alias WeGoNext.Mechanics.Taxonomy

  def boss(name, encounter_id, dbm_module_id, dbm_module_map_id, zone_id) do
    %{
      name: name,
      encounter_id: encounter_id,
      dbm_module_id: dbm_module_id,
      dbm_module_map_id: dbm_module_map_id,
      zone_id: zone_id
    }
  end

  def mechanic(
        raid_name,
        raid_slug,
        boss_name,
        encounter_id,
        spell_id,
        name,
        type,
        event,
        sources,
        opts \\ []
      ) do
    %{
      raid_name: raid_name,
      raid_slug: raid_slug,
      spell_id: spell_id,
      name: name,
      type: type || :unknown,
      event: event,
      boss_encounter_id: to_string(encounter_id),
      boss_name: boss_name,
      sources: sources,
      track: Keyword.get(opts, :track, false),
      rule: Keyword.get(opts, :rule, %{}),
      notes: Keyword.get(opts, :notes)
    }
  end

  def rule_criteria(mechanics) do
    mechanics
    |> Enum.filter(&fact_eligible?/1)
    |> Enum.map(&rule_criterion/1)
  end

  defp fact_eligible?(%{type: :avoidable, event: :damage_taken}), do: true

  defp fact_eligible?(%{type: :targeted_cone, event: :cast, rule: rule}) when rule != %{},
    do: true

  defp fact_eligible?(_mechanic), do: false

  defp rule_criterion(mechanic) do
    %{
      "spell_id" => mechanic.spell_id,
      "spell_name" => mechanic.name,
      "mechanic_type" => Atom.to_string(mechanic.type),
      "boss_encounter_id" => mechanic.boss_encounter_id,
      "boss_name" => mechanic.boss_name,
      "threshold" => threshold(mechanic),
      "notes" => notes(mechanic),
      "active" => true
    }
  end

  defp threshold(%{rule: %{max_hits: max_hits}}), do: %{"max_hits" => max_hits}

  defp threshold(%{type: :targeted_cone, rule: rule}) do
    %{
      "target_marker_spell_id" => rule.target_marker_spell_id,
      "impact_spell_ids" => rule.impact_spell_ids,
      "hit_debuff_spell_ids" => Map.get(rule, :hit_debuff_spell_ids, []),
      "max_safe_hit_count" => rule.max_safe_hit_count,
      "target_role_policy" => Atom.to_string(rule.target_role_policy),
      "allowed_collateral_roles" => Enum.map(rule.allowed_collateral_roles, &Atom.to_string/1),
      "position_evidence" => Atom.to_string(rule.position_evidence)
    }
  end

  defp threshold(%{type: :avoidable, event: :damage_taken}),
    do: Taxonomy.default_threshold(:avoidable)

  defp threshold(%{rule: %{must_interrupt: must_interrupt}}),
    do: %{"must_interrupt" => must_interrupt}

  defp threshold(_mechanic), do: %{}

  defp notes(mechanic) do
    sources =
      mechanic
      |> Map.get(:sources, [])
      |> Enum.map(&Atom.to_string/1)
      |> Enum.join(", ")

    ["raid: #{mechanic.raid_name}", "sources: #{sources}", Map.get(mechanic, :notes)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" | ")
  end
end
