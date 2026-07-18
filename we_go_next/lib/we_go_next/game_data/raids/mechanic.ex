defmodule WeGoNext.GameData.Raids.Mechanic do
  @moduledoc """
  Authored current-tier mechanic configuration.

  These configs express product intent. `source_annotations` record the external
  or observed evidence that informed that intent; they never make a source-data
  import an active rule by themselves.
  """

  alias WeGoNext.Mechanics.Taxonomy

  @evidence_families [
    :cast,
    :damage_taken,
    :debuff_application,
    :interrupt_opportunity
  ]

  @definition_origins [:authored_catalog]
  @source_annotations [
    :bigwigs,
    :combat_log,
    :dbm,
    :guide,
    :journal,
    :local_logs,
    :reminder,
    :source_reference,
    :warcraft_logs,
    :wowanalyzer
  ]

  @enforce_keys [
    :raid_name,
    :raid_slug,
    :boss_name,
    :boss_encounter_id,
    :spell_id,
    :name,
    :mechanic_type,
    :evidence_family,
    :definition_origin,
    :source_annotations,
    :default_actionability,
    :default_fact_eligibility
  ]
  defstruct @enforce_keys ++ [rule: %{}, notes: nil]

  @type evidence_family ::
          :cast | :damage_taken | :debuff_application | :interrupt_opportunity
  @type definition_origin :: :authored_catalog
  @type source_annotation ::
          :bigwigs
          | :combat_log
          | :dbm
          | :guide
          | :journal
          | :local_logs
          | :reminder
          | :source_reference
          | :warcraft_logs
          | :wowanalyzer

  @type t :: %__MODULE__{
          raid_name: String.t(),
          raid_slug: String.t(),
          boss_name: String.t(),
          boss_encounter_id: String.t(),
          spell_id: pos_integer(),
          name: String.t(),
          mechanic_type: atom(),
          evidence_family: evidence_family(),
          definition_origin: definition_origin(),
          source_annotations: [source_annotation()],
          default_actionability: :actionable | :context | :suppressed | :unknown,
          default_fact_eligibility: :supported | :provisional | :observation_only | :suppressed,
          rule: map(),
          notes: String.t() | nil
        }

  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    mechanic_type = Map.fetch!(attrs, :mechanic_type)
    classification = Taxonomy.fetch!(mechanic_type)

    attrs =
      attrs
      |> Map.put_new(:definition_origin, :authored_catalog)
      |> Map.put(:default_actionability, classification.actionability)
      |> Map.put(:default_fact_eligibility, classification.fact_eligibility)

    validate_inclusion!(attrs, :evidence_family, @evidence_families)
    validate_inclusion!(attrs, :definition_origin, @definition_origins)

    attrs
    |> Map.fetch!(:source_annotations)
    |> Enum.each(fn source ->
      unless source in @source_annotations do
        raise ArgumentError, "unsupported source annotation: #{inspect(source)}"
      end
    end)

    struct!(__MODULE__, attrs)
  end

  @doc "Returns whether this exact config has supported rule/fact semantics today."
  @spec rule_seed_eligible?(t()) :: boolean()
  def rule_seed_eligible?(%__MODULE__{
        mechanic_type: :avoidable,
        evidence_family: :damage_taken
      }),
      do: true

  def rule_seed_eligible?(%__MODULE__{
        mechanic_type: :targeted_cone,
        evidence_family: :cast,
        rule: rule
      })
      when rule != %{},
      do: true

  def rule_seed_eligible?(%__MODULE__{}), do: false

  defp validate_inclusion!(attrs, key, allowed) do
    value = Map.fetch!(attrs, key)

    unless value in allowed do
      raise ArgumentError, "unsupported #{key}: #{inspect(value)}"
    end
  end
end
