defmodule WeGoNext.StateTable do
  @moduledoc "Small compile-checked transition tables. Guards and effects remain named pure functions."

  defmacro __using__(_opts) do
    quote do
      @before_compile WeGoNext.StateTable
    end
  end

  defmacro __before_compile__(env) do
    states = Module.get_attribute(env.module, :states)
    events = Module.get_attribute(env.module, :events)
    guards = Module.get_attribute(env.module, :guards)
    effects = Module.get_attribute(env.module, :effects)
    rows = Module.get_attribute(env.module, :rows)
    validate!(states, events, guards, effects, rows)

    quote do
      def states, do: unquote(states)
      def events, do: unquote(events)
      def rows, do: unquote(Macro.escape(rows))
      def matrix, do: WeGoNext.StateTable.matrix(rows())
      def diagram, do: WeGoNext.StateTable.diagram(rows())
    end
  end

  def validate!(states, events, guards, effects, rows) do
    Enum.each(rows, &validate_names!(&1, states, events, guards, effects))

    for state <- states, event <- events do
      matching = Enum.filter(rows, fn {s, e, _, _, _} -> s == state and e == event end)

      unless matching != [] and elem(List.last(matching), 2) == :always and
               Enum.count(matching, &(elem(&1, 2) == :always)) == 1 do
        raise ArgumentError, "Unhandled or ambiguous transition: #{state}/#{event}"
      end
    end
  end

  defp validate_names!({from, event, guard, to, actions} = row, states, events, guards, effects) do
    known = [
      from in states,
      to in states,
      event in events,
      guard in guards,
      Enum.all?(actions, &(&1 in effects))
    ]

    unless Enum.all?(known), do: raise(ArgumentError, "Unknown transition name: #{inspect(row)}")
  end

  def step(rows, state, event, ctx, guard, reduce) do
    case Enum.find(rows, fn {from, on, condition, _, _} ->
           from == state and on == event and guard.(condition, ctx)
         end) do
      nil -> :invalid
      {_, _, _, to, effects} -> {:ok, to, Enum.reduce(effects, ctx, reduce), effects}
    end
  end

  def matrix(rows) do
    "| From | Event | Guard | To | Effects |\n|---|---|---|---|---|\n" <>
      Enum.map_join(rows, "\n", fn {from, event, guard, to, effects} ->
        "| #{from} | #{event} | #{guard} | #{to} | #{Enum.join(effects, ", ")} |"
      end) <> "\n"
  end

  def diagram(rows) do
    "stateDiagram-v2\n" <>
      Enum.map_join(
        Enum.reject(rows, fn {from, _, _, to, effects} ->
          from == to and effects == []
        end),
        "\n",
        fn {from, event, guard, to, _} ->
          "  #{from} --> #{to}: #{event} [#{guard}]"
        end
      ) <> "\n"
  end
end
