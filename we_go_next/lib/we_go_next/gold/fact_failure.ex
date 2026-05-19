defmodule WeGoNext.Gold.FactFailure do
  @moduledoc """
  Gold fact row for mechanic failures by encounter, player, and criterion.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer}
  alias WeGoNext.Gold.FactFailure.Rebuilder

  @primary_key false
  @schema_prefix "gold"

  schema "fact_failure" do
    field(:ruleset_id, :integer)
    field(:ruleset_version, :integer)
    field(:product, :string, default: "wow")
    field(:channel, :string, default: "retail")
    field(:build_version, :string)
    field(:build_key, :string)
    field(:failure_count, :integer)
    field(:total_damage, :integer, default: 0)

    belongs_to(:encounter, DimEncounter, foreign_key: :encounter_dim_id, primary_key: true)
    belongs_to(:player, DimPlayer, foreign_key: :player_dim_id, primary_key: true)

    belongs_to(:criterion, DimMechanicCriterion,
      foreign_key: :criterion_dim_id,
      primary_key: true
    )
  end

  @doc false
  def changeset(fact_failure, attrs) do
    fact_failure
    |> cast(attrs, [
      :encounter_dim_id,
      :player_dim_id,
      :criterion_dim_id,
      :ruleset_id,
      :ruleset_version,
      :product,
      :channel,
      :build_version,
      :build_key,
      :failure_count,
      :total_damage
    ])
    |> validate_required([
      :encounter_dim_id,
      :player_dim_id,
      :criterion_dim_id,
      :ruleset_id,
      :ruleset_version,
      :product,
      :channel,
      :failure_count,
      :total_damage
    ])
  end

  @doc """
  Rebuilds mechanic failure facts for one gold encounter dimension.
  """
  @spec rebuild_for_encounter(pos_integer(), keyword()) ::
          {:ok, %{deleted: non_neg_integer(), inserted: non_neg_integer()}} | {:error, term()}
  def rebuild_for_encounter(encounter_dim_id, opts \\ [ruleset: :active])
      when is_integer(encounter_dim_id) and is_list(opts) do
    Rebuilder.rebuild_for_encounter(encounter_dim_id, opts)
  end
end
