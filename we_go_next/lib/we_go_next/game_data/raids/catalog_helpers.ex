defmodule WeGoNext.GameData.Raids.CatalogHelpers do
  @moduledoc false

  alias WeGoNext.GameData.Raids.Mechanic
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

  def mechanic(raid_name, raid_slug, attrs, opts \\ []) do
    attrs
    |> Map.update!(:boss_encounter_id, &to_string/1)
    |> Map.put(:raid_name, raid_name)
    |> Map.put(:raid_slug, raid_slug)
    |> Map.put(:definition_origin, :authored_catalog)
    |> Map.put(:rule, Keyword.get(opts, :rule, %{}))
    |> Map.put(:notes, Keyword.get(opts, :notes))
    |> Mechanic.new!()
  end

  def rule_criteria(mechanics) do
    mechanics
    |> Enum.filter(&Mechanic.rule_seed_eligible?/1)
    |> Enum.map(&rule_criterion/1)
  end

  defp rule_criterion(mechanic) do
    %{
      "spell_id" => mechanic.spell_id,
      "spell_name" => mechanic.name,
      "mechanic_type" => Atom.to_string(mechanic.mechanic_type),
      "boss_encounter_id" => mechanic.boss_encounter_id,
      "boss_name" => mechanic.boss_name,
      "threshold" => threshold(mechanic),
      "notes" => notes(mechanic),
      "active" => true
    }
  end

  defp threshold(%{rule: %{max_hits: max_hits}}), do: %{"max_hits" => max_hits}

  defp threshold(%{mechanic_type: :targeted_cone, rule: rule}) do
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

  defp threshold(%{mechanic_type: :avoidable, evidence_family: :damage_taken}),
    do: Taxonomy.default_threshold(:avoidable)

  defp threshold(%{rule: %{must_interrupt: must_interrupt}}),
    do: %{"must_interrupt" => must_interrupt}

  defp threshold(_mechanic), do: %{}

  defp notes(mechanic) do
    sources =
      mechanic
      |> Map.get(:source_annotations, [])
      |> Enum.map_join(", ", &Atom.to_string/1)

    ["raid: #{mechanic.raid_name}", "sources: #{sources}", Map.get(mechanic, :notes)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" | ")
  end
end
