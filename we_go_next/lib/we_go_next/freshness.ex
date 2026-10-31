defmodule WeGoNext.Freshness do
  @moduledoc """
  Pure per-pull freshness classification. Missing stamps never prove freshness,
  including pulls with zero facts. `-1` reserves the failure stamp for an
  incomplete coordinated rebuild (database and document are not yet consistent).

  Components are independent; adapters choose the components their output needs.
  """
  alias WeGoNext.Gold.FactFailure.Derivation
  alias WeGoNext.Gold.FactWipeCause
  alias WeGoNext.Silver.DeathDerivation

  @table [
    {:partial, :partial_stamp},
    {:missing, :missing_stamp},
    {:current, :equal_stamp},
    {:stale, :always}
  ]

  def table, do: @table
  def partial_stamp, do: -1

  def current_versions do
    %{
      silver_death_derivation_version: DeathDerivation.current_version(),
      failure_derivation_version: Derivation.current_version(),
      wipe_cause_derivation_version: FactWipeCause.current_version(),
      derivation_version: Derivation.current_version()
    }
  end

  def classify(stamps) when is_map(stamps) do
    versions = current_versions()

    %{
      silver_deaths: stamp(stamps, versions, :silver_death_derivation_version),
      failures: stamp(stamps, versions, :failure_derivation_version),
      wipe_cause: stamp(stamps, versions, :wipe_cause_derivation_version),
      document: stamp(stamps, versions, :derivation_version)
    }
  end

  def current?(stamps, components) do
    statuses = classify(stamps)
    Enum.all?(List.wrap(components), &(Map.fetch!(statuses, &1) == :current))
  end

  defp stamp(stamps, versions, key) do
    actual = Map.get(stamps, key)
    expected = Map.fetch!(versions, key)
    {status, _guard} = Enum.find(@table, fn {_, guard} -> matches?(guard, actual, expected) end)
    status
  end

  defp matches?(:partial_stamp, -1, _), do: true
  defp matches?(:partial_stamp, _, _), do: false
  defp matches?(:missing_stamp, nil, _), do: true
  defp matches?(:missing_stamp, _, _), do: false
  defp matches?(:equal_stamp, actual, expected), do: actual == expected
  defp matches?(:always, _, _), do: true
end
