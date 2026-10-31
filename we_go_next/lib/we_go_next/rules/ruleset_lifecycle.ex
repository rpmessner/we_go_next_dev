defmodule WeGoNext.Rules.RulesetLifecycle do
  @moduledoc "Pure ruleset lifecycle. Replacement is authorized only by the activation transaction."
  use WeGoNext.StateTable

  @states ~w(draft active archived)a
  @events ~w(sync activate archive replace reset)a
  @guards [:always, :replacement]
  @effects [:activate, :archive, :reject]
  @transitions [
    {:draft, :sync, :always, :draft, []},
    {:active, :sync, :always, :active, []},
    {:archived, :sync, :always, :archived, []},
    {:draft, :activate, :always, :active, [:activate]},
    {:active, :activate, :always, :active, []},
    {:archived, :activate, :always, :active, [:activate]},
    {:draft, :archive, :always, :archived, [:archive]},
    {:archived, :archive, :always, :archived, []},
    {:active, :replace, :replacement, :archived, [:archive]},
    {:draft, :reset, :always, :draft, []}
  ]
  @rows @transitions ++
          for(
            state <- @states,
            event <- @events,
            not Enum.any?(@transitions, fn {from, on, guard, _, _} ->
              from == state and on == event and guard == :always
            end),
            do: {state, event, :always, state, [:reject]}
          )

  def step(state, event, ctx \\ %{}) do
    case WeGoNext.StateTable.step(@rows, state, event, ctx, &guard/2, &reduce/2) do
      {:ok, _, _, [:reject]} -> :invalid
      result -> result
    end
  end

  defp guard(:always, _ctx), do: true
  defp guard(:replacement, ctx), do: Map.get(ctx, :replacement, false)
  defp reduce(_effect, ctx), do: ctx
end
