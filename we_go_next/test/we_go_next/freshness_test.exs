defmodule WeGoNext.FreshnessTest do
  use ExUnit.Case, async: true
  alias WeGoNext.Freshness

  test "the current stamp vector is current for every component" do
    assert Freshness.classify(Freshness.current_versions()) == %{
             document: :current,
             silver_deaths: :current,
             failures: :current,
             wipe_cause: :current
           }
  end

  test "exhaustive stamp vectors: current iff all required stamps equal their versions" do
    versions = Freshness.current_versions()
    keys = Map.keys(versions)

    vectors =
      Enum.reduce(keys, [%{}], fn key, vectors ->
        for vector <- vectors,
            value <- [nil, -1, 0, Map.fetch!(versions, key), 99],
            do: Map.put(vector, key, value)
      end)

    for vector <- vectors do
      result = Freshness.classify(vector)
      assert Map.values(result) |> Enum.all?(&(&1 in [:missing, :partial, :current, :stale]))
      assert Freshness.current?(vector, Map.keys(result)) == (vector == versions)

      for {component, key} <- [
            silver_deaths: :silver_death_derivation_version,
            failures: :failure_derivation_version,
            wipe_cause: :wipe_cause_derivation_version
          ] do
        assert result[component] == :current == (vector[key] == versions[key])
        if is_nil(vector[key]), do: assert(result[component] == :missing)
        if vector[key] == -1, do: assert(result[component] == :partial)
      end
    end
  end

  test "an incomplete rebuild cannot be current even when every version matches" do
    stamps = Map.put(Freshness.current_versions(), :failure_derivation_version, -1)
    assert Freshness.classify(stamps).failures == :partial
    refute Freshness.current?(stamps, [:document, :silver_deaths, :failures, :wipe_cause])
  end
end
