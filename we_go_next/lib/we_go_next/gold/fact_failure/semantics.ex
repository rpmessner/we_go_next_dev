defmodule WeGoNext.Gold.FactFailure.Semantics do
  @moduledoc """
  Per-mechanic semantics versions used in public mirror criterion identity.
  """

  alias WeGoNext.Gold.DimMechanicCriterion
  alias WeGoNext.Gold.FactFailure.Builders.{AvoidableDamage, MissedInterrupt, TargetedCone}

  @versions %{
    "avoidable" => AvoidableDamage.semantics_version(),
    "interrupt" => MissedInterrupt.semantics_version(),
    "targeted_cone" => TargetedCone.semantics_version(),
    "soak" => 1,
    "spread" => 1,
    "stack" => 1,
    "tank_mechanic" => 1,
    "healer_mechanic" => 1
  }

  @doc """
  Returns the criterion semantics version for a supported mechanic type.
  """
  @spec version_for!(String.t() | atom()) :: pos_integer()
  def version_for!(mechanic_type) when is_atom(mechanic_type) do
    mechanic_type
    |> Atom.to_string()
    |> version_for!()
  end

  def version_for!(mechanic_type) when is_binary(mechanic_type) do
    Map.fetch!(@versions, mechanic_type)
  end

  @doc false
  def guard_supported_mechanic_types! do
    missing = DimMechanicCriterion.mechanic_types() -- Map.keys(@versions)

    if missing != [] do
      raise "missing fact semantics versions for mechanic types: #{Enum.join(missing, ", ")}"
    end

    :ok
  end
end
