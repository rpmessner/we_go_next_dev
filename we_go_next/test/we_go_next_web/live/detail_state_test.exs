defmodule WeGoNextWeb.EncounterLive.DetailStateTest do
  use ExUnit.Case, async: true
  alias WeGoNextWeb.EncounterLive.DetailState, as: Machine

  test "controls preserve freshness and unrelated data across random event prefixes" do
    :rand.seed(:exsss, {9, 18, 31})

    events = [
      {:params, "damage"},
      {:params, "unknown"},
      {:switch_tab, "deaths"},
      :toggle_untagged_mechanics,
      :toggle_player_debuffs,
      {:toggle_death_heals, "one"},
      {:toggle_death_heals, "two"},
      {:select_personal_player, "Player-One"},
      {:select_personal_player, "unknown"}
    ]

    for status <- Machine.states() do
      initial = %{Machine.initial() | players: [%{player_guid: "Player-One"}]}

      Enum.reduce(1..500, initial, fn _, ctx ->
        event = Enum.random(events)
        {:ok, ^status, next, effects} = Machine.step(status, event, ctx)

        assert next.active_tab in ~w(overview mechanics damage failures deaths interrupts personal)a

        assert is_boolean(next.show_untagged_mechanics)
        assert is_boolean(next.show_player_debuffs)
        assert MapSet.subset?(next.death_heal_keys, MapSet.new(["one", "two"]))
        assert next.players == ctx.players

        assert next.selected_personal_player ==
                 Enum.find(next.players, &(&1.player_guid == next.selected_personal_player_guid))

        assert :patch_tab in effects == match?({:switch_tab, _}, event)
        next
      end)
    end
  end

  test "each toggle is its own inverse in every document state" do
    for state <- Machine.states(),
        event <- [
          :toggle_untagged_mechanics,
          :toggle_player_debuffs,
          {:toggle_death_heals, "one"}
        ] do
      ctx = Machine.initial()
      {:ok, ^state, toggled, _} = Machine.step(state, event, ctx)
      refute toggled == ctx
      assert {:ok, ^state, ^ctx, _} = Machine.step(state, event, toggled)
    end
  end

  test "table artifacts match and unknown pairs are invalid" do
    root = Path.expand("../../../../docs/state-machines/encounter-detail", __DIR__)
    assert File.read!(Path.join(root, "implementation-matrix.md")) == Machine.matrix()
    assert File.read!(Path.join(root, "implementation.mmd")) == Machine.diagram()
    assert Machine.step(:missing, :unknown, Machine.initial()) == :invalid
    assert Machine.step(:unknown, :params, Machine.initial()) == :invalid
  end
end
