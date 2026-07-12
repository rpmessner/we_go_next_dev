defmodule WeGoNext.Mechanics.Taxonomy do
  @moduledoc """
  Authoritative mechanic and actionability vocabulary.

  The taxonomy distinguishes rule-backed mechanic types from classifications
  that only suppress or describe observations. Fact eligibility states whether
  a classification has defensible persisted failure semantics today.
  """

  @enforce_keys [:key, :label, :kind, :actionability, :fact_eligibility]
  defstruct [:key, :label, :kind, :actionability, :fact_eligibility]

  @type fact_eligibility :: :supported | :provisional | :observation_only | :suppressed
  @type kind :: :rule | :observation
  @type t :: %__MODULE__{
          key: atom(),
          label: String.t(),
          kind: kind(),
          actionability: :actionable | :context | :suppressed | :unknown,
          fact_eligibility: fact_eligibility()
        }

  @entries [
    %{
      key: :avoidable,
      label: "Avoidable",
      kind: :rule,
      actionability: :actionable,
      fact_eligibility: :supported
    },
    %{
      key: :interrupt,
      label: "Interrupt",
      kind: :rule,
      actionability: :actionable,
      fact_eligibility: :provisional
    },
    %{
      key: :targeted_cone,
      label: "Targeted cone",
      kind: :rule,
      actionability: :actionable,
      fact_eligibility: :supported
    },
    %{
      key: :soak,
      label: "Soak",
      kind: :rule,
      actionability: :context,
      fact_eligibility: :observation_only
    },
    %{
      key: :spread,
      label: "Spread",
      kind: :rule,
      actionability: :context,
      fact_eligibility: :observation_only
    },
    %{
      key: :stack,
      label: "Stack",
      kind: :rule,
      actionability: :context,
      fact_eligibility: :observation_only
    },
    %{
      key: :tank_mechanic,
      label: "Tank mechanic",
      kind: :rule,
      actionability: :context,
      fact_eligibility: :observation_only
    },
    %{
      key: :healer_mechanic,
      label: "Healer mechanic",
      kind: :rule,
      actionability: :context,
      fact_eligibility: :observation_only
    },
    %{
      key: :unavoidable_background,
      label: "Unavoidable / background",
      kind: :observation,
      actionability: :suppressed,
      fact_eligibility: :suppressed
    },
    %{
      key: :irrelevant,
      label: "Irrelevant",
      kind: :observation,
      actionability: :suppressed,
      fact_eligibility: :suppressed
    },
    %{
      key: :unknown,
      label: "Unknown / unclassified",
      kind: :observation,
      actionability: :unknown,
      fact_eligibility: :observation_only
    }
  ]

  @by_key Map.new(@entries, &{&1.key, &1})

  @spec keys() :: [atom()]
  def keys, do: Enum.map(@entries, & &1.key)

  @spec fetch!(atom() | String.t()) :: t()
  def fetch!(key) when is_binary(key), do: key |> String.to_existing_atom() |> fetch!()
  def fetch!(key) when is_atom(key), do: struct!(__MODULE__, Map.fetch!(@by_key, key))

  @spec rule_types() :: [String.t()]
  def rule_types do
    for %{kind: :rule, key: key} <- @entries, do: Atom.to_string(key)
  end

  @spec default_threshold(atom() | String.t()) :: map()
  def default_threshold(key) do
    case fetch!(key).key do
      :avoidable -> %{"max_hits" => 0}
      :interrupt -> %{"must_interrupt" => true}
      _key -> %{}
    end
  end

  @spec fact_eligible?(atom() | String.t()) :: boolean()
  def fact_eligible?(key), do: fetch!(key).fact_eligibility == :supported

  @spec evidence_completeness([atom()], [atom()]) :: %{
          status: :complete | :missing | :not_declared,
          observed: [atom()],
          missing: [atom()]
        }
  def evidence_completeness(expected, observed) when is_list(expected) and is_list(observed) do
    expected = expected |> Enum.uniq() |> Enum.sort()
    observed = observed |> Enum.uniq() |> Enum.sort()
    missing = expected -- observed

    status =
      cond do
        expected == [] -> :not_declared
        missing == [] -> :complete
        true -> :missing
      end

    %{status: status, observed: observed, missing: missing}
  end
end
