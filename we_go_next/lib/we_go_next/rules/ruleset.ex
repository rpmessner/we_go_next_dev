defmodule WeGoNext.Rules.Ruleset do
  @moduledoc """
  Authored set of mechanic rules.

  The first rules layer supports one globally active ruleset. Draft rulesets can
  be edited, activated, and archived before their criteria are promoted into
  gold snapshots.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.Rules.MechanicCriterion

  @statuses ~w(draft active archived)

  @schema_prefix "rules"

  schema "ruleset" do
    field(:name, :string)
    field(:status, :string, default: "draft")
    field(:version, :integer, default: 1)
    field(:product, :string, default: "wow")
    field(:channel, :string, default: "retail")
    field(:build_version, :string)
    field(:build_key, :string)
    field(:activated_at, :utc_datetime_usec)
    field(:archived_at, :utc_datetime_usec)

    has_many(:mechanic_criteria, MechanicCriterion)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(ruleset, attrs) do
    ruleset
    |> cast(attrs, [
      :name,
      :status,
      :version,
      :product,
      :channel,
      :build_version,
      :build_key,
      :activated_at,
      :archived_at
    ])
    |> validate_required([:name, :status, :version, :product, :channel])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:version, greater_than: 0)
    |> unique_constraint(:status, name: :ruleset_one_active_index)
    |> unique_constraint([:name, :version], name: :ruleset_name_version_index)
  end

  def statuses, do: @statuses
end
