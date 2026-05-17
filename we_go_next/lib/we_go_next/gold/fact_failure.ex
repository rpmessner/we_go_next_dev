defmodule WeGoNext.Gold.FactFailure do
  @moduledoc """
  Gold fact row for mechanic failures by encounter, player, and criterion.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.Criteria.MechanicCriteria
  alias WeGoNext.Encounters.Encounter
  alias WeGoNext.Gold.DimPlayer

  @primary_key false
  @schema_prefix "gold"

  schema "fact_failure" do
    field(:failure_count, :integer)
    field(:total_damage, :integer, default: 0)

    belongs_to(:encounter, Encounter, primary_key: true)
    belongs_to(:player, DimPlayer, foreign_key: :player_dim_id, primary_key: true)
    belongs_to(:criterion, MechanicCriteria, primary_key: true)
  end

  @doc false
  def changeset(fact_failure, attrs) do
    fact_failure
    |> cast(attrs, [
      :encounter_id,
      :player_dim_id,
      :criterion_id,
      :failure_count,
      :total_damage
    ])
    |> validate_required([
      :encounter_id,
      :player_dim_id,
      :criterion_id,
      :failure_count,
      :total_damage
    ])
  end
end
