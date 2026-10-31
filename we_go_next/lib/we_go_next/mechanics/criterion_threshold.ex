defmodule WeGoNext.Mechanics.CriterionThreshold do
  @moduledoc "Threshold validation for the live gold mechanics catalog."
  import Ecto.Changeset

  alias WeGoNext.Mechanics.Taxonomy

  @targeted_cone_required_keys ~w(
    target_marker_spell_id
    impact_spell_ids
    max_safe_hit_count
    target_role_policy
    allowed_collateral_roles
    position_evidence
  )
  @targeted_cone_optional_keys ~w(hit_debuff_spell_ids)
  @targeted_cone_role_policies ~w(any tank non_tank)
  @targeted_cone_roles ~w(tank healer dps unknown)
  @position_evidence_modes ~w(ignored optional required)

  def validate(changeset) do
    changeset
    |> normalize_interrupt_threshold()
    |> validate_threshold()
  end

  defp normalize_interrupt_threshold(changeset) do
    if get_field(changeset, :mechanic_type) == "interrupt" and
         get_field(changeset, :threshold) in [
           nil,
           %{}
         ] do
      put_change(changeset, :threshold, Taxonomy.default_threshold(:interrupt))
    else
      changeset
    end
  end

  defp validate_threshold(changeset) do
    case {get_field(changeset, :mechanic_type), get_field(changeset, :threshold)} do
      {"avoidable", threshold} ->
        validate_avoidable_threshold(changeset, threshold)

      {"interrupt", threshold} ->
        validate_interrupt_threshold(changeset, threshold)

      {"targeted_cone", threshold} ->
        validate_targeted_cone_threshold(changeset, threshold)

      {type, threshold}
      when type in ~w(soak spread stack tank_mechanic healer_mechanic) ->
        validate_empty_threshold(changeset, threshold)

      _ ->
        changeset
    end
  end

  defp validate_avoidable_threshold(changeset, %{"max_hits" => max_hits} = threshold)
       when map_size(threshold) == 1 and is_integer(max_hits) and max_hits >= 0,
       do: changeset

  defp validate_avoidable_threshold(changeset, _threshold) do
    add_error(changeset, :threshold, "must contain only max_hits as a non-negative integer")
  end

  defp validate_interrupt_threshold(changeset, %{"must_interrupt" => must_interrupt} = threshold)
       when map_size(threshold) == 1 and is_boolean(must_interrupt),
       do: changeset

  defp validate_interrupt_threshold(changeset, _threshold) do
    add_error(changeset, :threshold, "must contain only must_interrupt as a boolean")
  end

  defp validate_targeted_cone_threshold(changeset, threshold) when is_map(threshold) do
    cond do
      not targeted_cone_keys_valid?(threshold) ->
        targeted_cone_error(changeset)

      not positive_integer?(threshold["target_marker_spell_id"]) ->
        targeted_cone_error(changeset)

      not positive_integer_list?(threshold["impact_spell_ids"]) ->
        targeted_cone_error(changeset)

      not optional_hit_debuffs_valid?(threshold) ->
        targeted_cone_error(changeset)

      not positive_integer?(threshold["max_safe_hit_count"]) ->
        targeted_cone_error(changeset)

      not targeted_cone_roles_valid?(threshold) ->
        targeted_cone_error(changeset)

      threshold["position_evidence"] not in @position_evidence_modes ->
        targeted_cone_error(changeset)

      true ->
        changeset
    end
  end

  defp validate_targeted_cone_threshold(changeset, _threshold), do: targeted_cone_error(changeset)

  defp targeted_cone_roles_valid?(threshold) do
    threshold["target_role_policy"] in @targeted_cone_role_policies and
      role_list?(threshold["allowed_collateral_roles"])
  end

  defp targeted_cone_keys_valid?(threshold) do
    allowed_keys = @targeted_cone_required_keys ++ @targeted_cone_optional_keys

    Enum.all?(@targeted_cone_required_keys, &Map.has_key?(threshold, &1)) and
      Enum.all?(Map.keys(threshold), &(&1 in allowed_keys))
  end

  defp optional_hit_debuffs_valid?(threshold) do
    not Map.has_key?(threshold, "hit_debuff_spell_ids") or
      positive_integer_list?(threshold["hit_debuff_spell_ids"])
  end

  defp targeted_cone_error(changeset) do
    add_error(
      changeset,
      :threshold,
      "must define target marker, impact spells, safe hit count, role policy, allowed collateral roles, and position evidence"
    )
  end

  defp validate_empty_threshold(changeset, threshold) when threshold in [nil, %{}], do: changeset

  defp validate_empty_threshold(changeset, _threshold) do
    add_error(changeset, :threshold, "must be empty until this mechanic type has fact semantics")
  end

  defp positive_integer?(value), do: is_integer(value) and value > 0

  defp positive_integer_list?(values) when is_list(values) and values != [] do
    Enum.all?(values, &positive_integer?/1)
  end

  defp positive_integer_list?(_values), do: false

  defp role_list?(roles) when is_list(roles), do: Enum.all?(roles, &(&1 in @targeted_cone_roles))
  defp role_list?(_roles), do: false
end
