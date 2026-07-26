defmodule WeGoNext.Gold.DeathSurvival do
  @moduledoc """
  Per-death survival analysis: the read-model input for death cards and the
  encounter document section (we-41).

  For one `silver.death` row plus the player's silver context, resolves the
  player's survival kit into states over the same fixed-seconds window the
  recap captured:

    * `:died_through` — a catalog aura window was still active at the moment
      of death (observed).
    * `:used_in_window` — a usage row inside the death window (observed).
    * `:on_cooldown` — a prior use implies the action (or its shared
      consumable cooldown group / per-combat allowance) was still spent at
      death. **Inference**: encounter-start cooldown state is unknown.
    * `:not_talented` — the talent loadout excludes the action (observed).
    * `:unknown` — talent data or entry mapping missing; never reported as
      "didn't have it".
    * `:available_unused` — everything else: likely available. **Inference.**

  Every kit entry carries `basis: :observed | :inferred` so read models and
  UI must label cooldown/availability claims as inference. Externals cast on
  the player inside the window are reported display-only, with no
  availability inference (their cooldowns belong to the caster).
  """

  alias WeGoNext.GameData.SurvivalActions

  @default_window_ms 10_000

  @doc """
  Analyzes one death against the player's silver context.

  * `death` — a `silver.death` row (map or struct) with
    `died_at_ms_into_fight`, `window_ms`, and `target_guid`.
  * `player_info` — the player's `silver.player_info` row or nil when no
    COMBATANT_INFO was captured.
  * `survival_actions` — the encounter's `silver.survival_action` rows (any
    superset; filtered here by caster/target).
  * `defensive_buff_windows` — the encounter's `silver.defensive_buff_window`
    rows (any superset; filtered here by target).
  """
  def analyze(death, player_info, survival_actions, defensive_buff_windows) do
    target_guid = death.target_guid
    died_at_ms = death.died_at_ms_into_fight
    window_ms = death.window_ms || @default_window_ms
    window_start_ms = died_at_ms - window_ms

    spec_id = player_info && player_info.spec_id
    talents = player_info && player_info.talents

    availability =
      Map.new(SurvivalActions.availability_for(spec_id, talents), &{&1.key, &1.state})

    uses_by_key =
      survival_actions
      |> Enum.filter(&(&1.caster_guid == target_guid and &1.used_at_ms_into_fight <= died_at_ms))
      |> Enum.group_by(&action_key/1)
      |> Map.delete(nil)

    active_aura_spell_ids =
      defensive_buff_windows
      |> Enum.filter(fn window ->
        window.target_guid == target_guid and
          window.started_at_ms_into_fight <= died_at_ms and
          (window.ended_at_ms_into_fight == nil or
             window.ended_at_ms_into_fight >= died_at_ms)
      end)
      |> MapSet.new(& &1.spell_id)

    kit =
      spec_id
      |> SurvivalActions.kit_for()
      |> Enum.map(fn action ->
        kit_entry(
          action,
          Map.get(availability, action.key, :unknown),
          uses_by_key,
          active_aura_spell_ids,
          died_at_ms,
          window_start_ms
        )
      end)

    externals_received =
      survival_actions
      |> Enum.filter(fn row ->
        row.target_guid == target_guid and row.caster_guid != target_guid and
          row.used_at_ms_into_fight in window_start_ms..died_at_ms
      end)
      |> Enum.sort_by(& &1.used_at_ms_into_fight)
      |> Enum.map(
        &Map.take(&1, [:spell_id, :spell_name, :caster_guid, :category, :used_at_ms_into_fight])
      )

    %{
      target_guid: target_guid,
      died_at_ms_into_fight: died_at_ms,
      window_ms: window_ms,
      kit: kit,
      externals_received: externals_received
    }
  end

  defp kit_entry(
         action,
         availability,
         uses_by_key,
         active_aura_spell_ids,
         died_at_ms,
         window_start_ms
       ) do
    uses = Map.get(uses_by_key, action.key, [])
    last_use = Enum.max_by(uses, & &1.used_at_ms_into_fight, fn -> nil end)
    used_in_window = last_use && last_use.used_at_ms_into_fight >= window_start_ms

    {state, basis} =
      cond do
        died_through?(action, active_aura_spell_ids) ->
          {:died_through, :observed}

        used_in_window ->
          {:used_in_window, :observed}

        # An observed earlier use proves possession regardless of what the
        # talent data says, so cooldown inference outranks unknown/untalented.
        spent_at_death?(action, uses, uses_by_key, died_at_ms) ->
          {:on_cooldown, :inferred}

        availability == :not_talented ->
          {:not_talented, :observed}

        availability == :unknown ->
          {:unknown, :observed}

        true ->
          {:available_unused, :inferred}
      end

    %{
      key: action.key,
      name: action.name,
      kind: action.kind,
      category: action.category,
      effect_kind: action.effect_kind,
      availability: availability,
      state: state,
      basis: basis,
      used_at_ms_into_fight: if(used_in_window, do: last_use.used_at_ms_into_fight),
      last_used_at_ms_into_fight: last_use && last_use.used_at_ms_into_fight
    }
  end

  defp died_through?(action, active_aura_spell_ids) do
    Enum.any?(action.aura_spell_ids, &MapSet.member?(active_aura_spell_ids, &1))
  end

  # Cooldown inference from observed uses only: base cooldown per charge,
  # the shared consumable cooldown group, and the per-combat allowance.
  # Encounter-start state is unknown, so this can only ever claim "spent",
  # never prove "ready" — hence available_unused stays an inference too.
  defp spent_at_death?(action, uses, uses_by_key, died_at_ms) do
    cooldown_relevant_uses =
      case action.shared_cooldown_group do
        nil ->
          uses

        group ->
          for {key, key_uses} <- uses_by_key,
              shared_group(key) == group,
              use <- key_uses,
              do: use
      end

    uses_within_cooldown =
      Enum.count(
        cooldown_relevant_uses,
        &(&1.used_at_ms_into_fight > died_at_ms - action.base_cooldown_ms)
      )

    exhausted_per_combat =
      action.max_uses_per_combat != nil and length(uses) >= action.max_uses_per_combat

    uses_within_cooldown >= action.charges or exhausted_per_combat
  end

  defp shared_group(key) do
    case Enum.find(SurvivalActions.all(), &(&1.key == key)) do
      nil -> nil
      action -> action.shared_cooldown_group
    end
  end

  defp action_key(row) do
    case SurvivalActions.get_by_cast_id(row.spell_id) do
      nil -> nil
      action -> action.key
    end
  end
end
