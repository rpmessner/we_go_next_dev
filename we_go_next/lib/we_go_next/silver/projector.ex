defmodule WeGoNext.Silver.Projector do
  @moduledoc """
  Projects normalized combat-log events into canonical silver table grains.

  The native parser owns byte scanning and event normalization. This module owns
  the Elixir/domain projection from those normalized events into medallion rows.
  """

  import Bitwise

  alias WeGoNext.GameData.{Interrupts, SurvivalActions}
  alias WeGoNext.Silver.Projection
  alias WeGoNext.WowClass

  @damage_taken_types ~w(SPELL_DAMAGE SPELL_PERIODIC_DAMAGE SWING_DAMAGE RANGE_DAMAGE ENVIRONMENTAL_DAMAGE)
  @damage_done_types ~w(SPELL_DAMAGE SPELL_PERIODIC_DAMAGE SWING_DAMAGE RANGE_DAMAGE)
  @heal_taken_types ~w(SPELL_HEAL SPELL_PERIODIC_HEAL)
  @default_death_window_ms 10_000
  @death_window_event_cap 100
  @consumable_heal_join_window_ms 2_000

  @unknown_source_guid "__UNKNOWN_SOURCE_GUID__"
  @unknown_target_guid "__UNKNOWN_TARGET_GUID__"
  @unknown_player_name "__UNKNOWN_PLAYER__"
  @object_affiliation_group 0x00000007
  @object_reaction_friendly 0x00000010
  @object_reaction_hostile 0x00000040
  @object_control_player 0x00000100

  @doc """
  Returns table-shaped row lists for the silver tables.

  Options: `:death_window_ms` — the fixed-seconds death window bounding both
  the recap and window event capture (default #{@default_death_window_ms}).
  """
  def project(encounter_dim_id, events, opts \\ [])
      when is_integer(encounter_dim_id) and is_list(events) do
    indexed_events =
      events
      |> Enum.with_index()
      |> Enum.sort_by(fn {event, index} -> {time_ms(event), index} end)

    events = Enum.map(indexed_events, &elem(&1, 0))
    tank_guids = detect_tank_guids(events)
    survival_action = project_survival_actions(encounter_dim_id, events)
    death_window_ms = Keyword.get(opts, :death_window_ms, @default_death_window_ms)

    %Projection{
      damage_taken: project_damage_taken(encounter_dim_id, events),
      damage_taken_event: project_damage_taken_events(encounter_dim_id, indexed_events),
      damage_done: project_damage_done(encounter_dim_id, events, pet_owner_map(events)),
      death: project_deaths(encounter_dim_id, events, survival_action, death_window_ms),
      interrupt_opportunity: project_interrupt_opportunities(encounter_dim_id, events),
      debuff_application: project_debuff_applications(encounter_dim_id, events),
      defensive_buff_window: project_defensive_buff_windows(encounter_dim_id, events),
      survival_action: survival_action,
      player_info: project_player_info(encounter_dim_id, events, tank_guids)
    }
  end

  defp project_damage_taken_events(encounter_dim_id, indexed_events) do
    indexed_events
    |> Enum.filter(fn {event, _index} ->
      event_type(event) in @damage_taken_types and player_guid?(event_value(event, :target_guid))
    end)
    |> Enum.map(fn {event, index} ->
      %{
        encounter_dim_id: encounter_dim_id,
        combat_log_event_index: index,
        event_type: event_type(event),
        occurred_at_ms_into_fight: time_ms(event),
        timestamp: event_value(event, :timestamp),
        target_guid: normalize_guid(event_value(event, :target_guid), @unknown_target_guid),
        target_name: clean_optional_name(event_value(event, :target_name)),
        source_guid: normalize_guid(event_value(event, :source_guid), @unknown_source_guid),
        source_name: event_value(event, :source_name),
        source_is_npc: npc_guid?(event_value(event, :source_guid)),
        spell_id: normalize_spell_id(event_value(event, :spell_id)),
        spell_name: event_value(event, :spell_name) || "Melee",
        spell_school: normalize_optional_integer(event_value(event, :spell_school)) || 1,
        amount: non_negative_integer(event_value(event, :amount)),
        overkill: non_negative_integer(event_value(event, :overkill))
      }
    end)
    |> Enum.sort_by(&{&1.occurred_at_ms_into_fight, &1.combat_log_event_index})
  end

  defp project_damage_taken(encounter_dim_id, events) do
    events
    |> Enum.filter(
      &(event_type(&1) in @damage_taken_types and player_guid?(event_value(&1, :target_guid)))
    )
    |> Enum.reduce(%{}, fn event, acc ->
      target_guid = normalize_guid(event_value(event, :target_guid), @unknown_target_guid)
      source_guid = normalize_guid(event_value(event, :source_guid), @unknown_source_guid)
      spell_id = normalize_spell_id(event_value(event, :spell_id))
      amount = non_negative_integer(event_value(event, :amount))
      overkill = non_negative_integer(event_value(event, :overkill))
      key = {target_guid, source_guid, spell_id}

      Map.update(
        acc,
        key,
        new_damage_taken_row(
          encounter_dim_id,
          event,
          target_guid,
          source_guid,
          spell_id,
          amount,
          overkill
        ),
        fn row ->
          %{
            row
            | total_amount: row.total_amount + amount,
              hit_count: row.hit_count + 1,
              max_hit: max(row.max_hit, amount),
              overkill_total: row.overkill_total + overkill
          }
        end
      )
    end)
    |> Map.values()
    |> Enum.sort_by(&{&1.target_guid, &1.source_guid, &1.spell_id})
  end

  defp new_damage_taken_row(
         encounter_dim_id,
         event,
         target_guid,
         source_guid,
         spell_id,
         amount,
         overkill
       ) do
    %{
      encounter_dim_id: encounter_dim_id,
      target_guid: target_guid,
      source_guid: source_guid,
      spell_id: spell_id,
      total_amount: amount,
      hit_count: 1,
      max_hit: amount,
      overkill_total: overkill,
      source_is_npc: npc_guid?(event_value(event, :source_guid))
    }
  end

  # Pets and guardians log damage under their own GUID. Their owning player is
  # recoverable from two places: SPELL_SUMMON (player summons the unit during
  # the encounter — wild imps, Xuen, Grimoire pets) and the advanced-block
  # owner GUID the parser surfaces on pet melee hits (covers permanent pets
  # summoned before the pull, which log no SPELL_SUMMON in the encounter
  # slice). Built as a full pass before aggregation so a pet's early spell
  # hits attribute even when the owning evidence appears later in the stream.
  defp pet_owner_map(events) do
    Enum.reduce(events, %{}, fn event, acc ->
      source_guid = event_value(event, :source_guid)
      target_guid = event_value(event, :target_guid)
      owner_guid = event_value(event, :owner_guid)

      cond do
        event_type(event) == "SPELL_SUMMON" and player_guid?(source_guid) and
            is_binary(target_guid) ->
          Map.put(acc, target_guid, source_guid)

        player_guid?(owner_guid) and is_binary(source_guid) and not player_guid?(source_guid) ->
          Map.put_new(acc, source_guid, owner_guid)

        true ->
          acc
      end
    end)
  end

  # Damage a player did directly, or that a pet the player owns did.
  defp damage_done_source_guid(event, pet_owners) do
    source_guid = event_value(event, :source_guid)

    if player_guid?(source_guid) do
      source_guid
    else
      Map.get(pet_owners, source_guid)
    end
  end

  defp project_damage_done(encounter_dim_id, events, pet_owners) do
    events
    |> Enum.filter(&(event_type(&1) in @damage_done_types))
    |> Enum.flat_map(fn event ->
      source_guid = damage_done_source_guid(event, pet_owners)

      if is_binary(source_guid) and npc_guid?(event_value(event, :target_guid)) do
        [{source_guid, event}]
      else
        []
      end
    end)
    |> Enum.reduce(%{}, fn {source_guid, event}, acc ->
      target_guid = normalize_guid(event_value(event, :target_guid), @unknown_target_guid)
      spell_id = normalize_spell_id(event_value(event, :spell_id))
      amount = non_negative_integer(event_value(event, :amount))
      key = {source_guid, target_guid, spell_id}

      Map.update(
        acc,
        key,
        new_damage_done_row(encounter_dim_id, source_guid, target_guid, spell_id, amount),
        fn row ->
          %{
            row
            | total_amount: row.total_amount + amount,
              hit_count: row.hit_count + 1,
              max_hit: max(row.max_hit, amount)
          }
        end
      )
    end)
    |> Map.values()
    |> Enum.sort_by(&{&1.source_guid, &1.target_guid, &1.spell_id})
  end

  defp new_damage_done_row(encounter_dim_id, source_guid, target_guid, spell_id, amount) do
    %{
      encounter_dim_id: encounter_dim_id,
      source_guid: source_guid,
      target_guid: target_guid,
      spell_id: spell_id,
      total_amount: amount,
      hit_count: 1,
      max_hit: amount
    }
  end

  # Deaths carry one fixed-seconds window (display and analysis share it):
  # every damage-taken, incoming-heal, and survival-action usage row within
  # `window_ms` before the death, interleaved in time order. The buffers hold
  # {seq, row} so same-millisecond combat events keep their log order; usage
  # rows (joined from the survival grain, which has no event seq) sort after
  # combat events on the same millisecond via a large tiebreak. Buffers are
  # time-trimmed on insert to the same window build_death applies, so
  # never-dying targets don't grow their buffer for the whole encounter.
  defp project_deaths(encounter_dim_id, events, survival_rows, window_ms) do
    usage_by_target = Enum.group_by(survival_rows, & &1.target_guid)

    {deaths, _windows} =
      events
      |> Enum.with_index()
      |> Enum.reduce({[], %{}}, fn {event, seq}, {deaths, windows} ->
        window_kind = death_window_kind(event)

        cond do
          event_type(event) == "UNIT_DIED" and
            event_value(event, :unconscious_on_death) != 1 and
              player_guid?(event_value(event, :target_guid)) ->
            target_guid = normalize_guid(event_value(event, :target_guid), @unknown_target_guid)

            death =
              build_death(
                encounter_dim_id,
                target_guid,
                time_ms(event),
                Map.get(windows, target_guid, []),
                Map.get(usage_by_target, target_guid, []),
                window_ms
              )

            {[death | deaths], Map.delete(windows, target_guid)}

          window_kind != nil and player_guid?(event_value(event, :target_guid)) ->
            target_guid = normalize_guid(event_value(event, :target_guid), @unknown_target_guid)
            entry = {seq, death_window_event(event, window_kind)}
            cutoff_ms = time_ms(event) - window_ms

            {deaths,
             Map.update(windows, target_guid, [entry], fn entries ->
               kept =
                 Enum.take_while(entries, fn {_seq, row} ->
                   row["ms_into_fight"] >= cutoff_ms
                 end)

               [entry | kept]
             end)}

          true ->
            {deaths, windows}
        end
      end)

    deaths
    |> Enum.reverse()
    |> Enum.sort_by(& &1.died_at_ms_into_fight)
  end

  defp build_death(encounter_dim_id, target_guid, died_at_ms, buffered, usage_rows, window_ms) do
    window_start_ms = died_at_ms - window_ms

    combat_entries =
      for {seq, row} <- buffered, row["ms_into_fight"] >= window_start_ms, do: {row, seq}

    usage_entries =
      usage_rows
      |> Enum.filter(&(&1.used_at_ms_into_fight in window_start_ms..died_at_ms))
      |> Enum.with_index(1_000_000_000)
      |> Enum.map(fn {row, tiebreak} -> {death_window_usage(row), tiebreak} end)

    sorted =
      (combat_entries ++ usage_entries)
      |> Enum.sort_by(fn {row, tiebreak} -> {row["ms_into_fight"], tiebreak} end)
      |> Enum.map(&elem(&1, 0))

    truncated = length(sorted) > @death_window_event_cap
    window_events = if truncated, do: Enum.take(sorted, -@death_window_event_cap), else: sorted

    recap =
      window_events
      |> Enum.filter(&(&1["kind"] == "damage"))
      |> Enum.reverse()
      |> Enum.map(&Map.delete(&1, "kind"))

    killing_blow = List.first(recap)

    %{
      encounter_dim_id: encounter_dim_id,
      target_guid: target_guid,
      died_at_ms_into_fight: died_at_ms,
      killing_blow_spell_id: killing_blow && killing_blow["spell_id"],
      killing_blow_source_guid: killing_blow && killing_blow["source_guid"],
      damage_recap: recap,
      window_ms: window_ms,
      window_truncated: truncated,
      window_events: window_events
    }
  end

  defp death_window_kind(event) do
    type = event_type(event)

    cond do
      type in @damage_taken_types -> "damage"
      type in @heal_taken_types -> "heal"
      true -> nil
    end
  end

  defp death_window_event(event, "damage") do
    %{
      "kind" => "damage",
      "timestamp" => event_value(event, :timestamp),
      "ms_into_fight" => time_ms(event),
      "spell_id" => normalize_spell_id(event_value(event, :spell_id)),
      "spell_name" => event_value(event, :spell_name) || "Melee",
      "source_guid" => normalize_guid(event_value(event, :source_guid), @unknown_source_guid),
      "source_name" => event_value(event, :source_name),
      "amount" => non_negative_integer(event_value(event, :amount)),
      "overkill" => non_negative_integer(event_value(event, :overkill)),
      "school" => event_value(event, :spell_school) || 1
    }
  end

  defp death_window_event(event, "heal") do
    %{
      "kind" => "heal",
      "timestamp" => event_value(event, :timestamp),
      "ms_into_fight" => time_ms(event),
      "spell_id" => normalize_spell_id(event_value(event, :spell_id)),
      "spell_name" => event_value(event, :spell_name),
      "source_guid" => normalize_guid(event_value(event, :source_guid), @unknown_source_guid),
      "source_name" => event_value(event, :source_name),
      "amount" => non_negative_integer(event_value(event, :amount)),
      "overheal" => non_negative_integer(event_value(event, :overhealing))
    }
  end

  defp death_window_usage(row) do
    %{
      "kind" => "survival_action",
      "ms_into_fight" => row.used_at_ms_into_fight,
      "spell_id" => row.spell_id,
      "spell_name" => row.spell_name,
      "caster_guid" => row.caster_guid,
      "action_kind" => row.kind,
      "category" => row.category,
      "heal_amount" => row.heal_amount,
      "overheal_amount" => row.overheal_amount
    }
  end

  defp project_interrupt_opportunities(encounter_dim_id, events) do
    interruptible_spell_ids = interruptible_spell_ids()

    {rows, _pending_casts} =
      Enum.reduce(events, {[], %{}}, fn event, {rows, pending_casts} ->
        spell_id = normalize_spell_id(event_value(event, :spell_id))
        source_guid = normalize_guid(event_value(event, :source_guid), @unknown_source_guid)
        target_guid = normalize_guid(event_value(event, :target_guid), @unknown_target_guid)
        interrupted_spell_id = normalize_spell_id(event_value(event, :extra_spell_id))

        cast_key = {source_guid, spell_id}
        interrupt_key = {target_guid, interrupted_spell_id}

        cond do
          interruptible_cast?(event, "SPELL_CAST_START", interruptible_spell_ids, spell_id) ->
            pending_cast =
              %{
                target_npc_guid: source_guid,
                interrupted_spell_id: spell_id
              }

            {rows, Map.put(pending_casts, cast_key, pending_cast)}

          player_interrupt?(event) ->
            row = %{
              encounter_dim_id: encounter_dim_id,
              target_npc_guid: target_guid,
              interrupted_spell_id: interrupted_spell_id,
              opportunity_ms_into_fight: time_ms(event),
              success: true,
              interrupter_guid: source_guid,
              interrupting_spell_id: spell_id
            }

            {[row | rows], Map.delete(pending_casts, interrupt_key)}

          interruptible_cast?(event, "SPELL_CAST_SUCCESS", interruptible_spell_ids, spell_id) ->
            complete_pending_cast(pending_casts, cast_key, rows, encounter_dim_id, event)

          true ->
            {rows, pending_casts}
        end
      end)

    rows
    |> Enum.reverse()
    |> Enum.sort_by(&{&1.opportunity_ms_into_fight, &1.target_npc_guid, &1.interrupted_spell_id})
  end

  defp interruptible_cast?(event, type, spell_ids, spell_id) do
    event_type(event) == type and hostile_npc_source?(event) and
      MapSet.member?(spell_ids, spell_id)
  end

  defp player_interrupt?(event) do
    event_type(event) == "SPELL_INTERRUPT" and player_guid?(event_value(event, :source_guid)) and
      hostile_npc_target?(event)
  end

  defp complete_pending_cast(pending_casts, key, rows, encounter_dim_id, event) do
    case Map.pop(pending_casts, key) do
      {nil, pending_casts} ->
        {rows, pending_casts}

      {pending_cast, pending_casts} ->
        row =
          Map.merge(pending_cast, %{
            encounter_dim_id: encounter_dim_id,
            opportunity_ms_into_fight: time_ms(event),
            success: false,
            interrupter_guid: nil,
            interrupting_spell_id: nil
          })

        {[row | rows], pending_casts}
    end
  end

  defp interruptible_spell_ids do
    Interrupts.spell_ids()
  end

  defp project_debuff_applications(encounter_dim_id, events) do
    {applications, pending} =
      Enum.reduce(events, {[], %{}}, fn event, {applications, pending} ->
        cond do
          debuff_event?(event, "SPELL_AURA_APPLIED") ->
            app = debuff_application_row(encounter_dim_id, event)
            key = {app.target_guid, app.spell_id}
            {applications, Map.update(pending, key, [app], &[app | &1])}

          debuff_event?(event, "SPELL_AURA_APPLIED_DOSE") ->
            {[debuff_application_row(encounter_dim_id, event) | applications], pending}

          debuff_event?(event, "SPELL_AURA_REMOVED") ->
            key = {
              normalize_guid(event_value(event, :target_guid), @unknown_target_guid),
              normalize_spell_id(event_value(event, :spell_id))
            }

            complete_debuff(pending, key, applications, event)

          true ->
            {applications, pending}
        end
      end)

    pending_apps =
      pending
      |> Map.values()
      |> List.flatten()

    (applications ++ pending_apps)
    |> Enum.reverse()
    |> Enum.sort_by(&{&1.applied_at_ms_into_fight, &1.target_guid, &1.spell_id})
  end

  defp complete_debuff(pending, key, applications, event) do
    case Map.get(pending, key) do
      [app | rest] ->
        completed_app = %{
          app
          | duration_ms: max(time_ms(event) - app.applied_at_ms_into_fight, 0)
        }

        {[completed_app | applications], update_pending(pending, key, rest)}

      _ ->
        {applications, pending}
    end
  end

  defp update_pending(pending, key, []), do: Map.delete(pending, key)
  defp update_pending(pending, key, rest), do: Map.put(pending, key, rest)

  defp debuff_event?(event, type) do
    event_type(event) == type and
      player_guid?(event_value(event, :target_guid)) and
      extra_value(event, :aura_type) == "DEBUFF"
  end

  defp debuff_application_row(encounter_dim_id, event) do
    %{
      encounter_dim_id: encounter_dim_id,
      target_guid: normalize_guid(event_value(event, :target_guid), @unknown_target_guid),
      source_guid: normalize_guid(event_value(event, :source_guid), @unknown_source_guid),
      spell_id: normalize_spell_id(event_value(event, :spell_id)),
      applied_at_ms_into_fight: time_ms(event),
      duration_ms: nil,
      stack_count: 1
    }
  end

  defp project_defensive_buff_windows(encounter_dim_id, events) do
    {windows, pending} =
      Enum.reduce(events, {[], %{}}, fn event, {windows, pending} ->
        cond do
          defensive_buff_event?(event, "SPELL_AURA_APPLIED") ->
            window = defensive_buff_window_row(encounter_dim_id, event)
            key = {window.target_guid, window.source_guid, window.spell_id}
            {windows, Map.update(pending, key, [window], &[window | &1])}

          defensive_buff_event?(event, "SPELL_AURA_REMOVED") ->
            key = {
              normalize_guid(event_value(event, :target_guid), @unknown_target_guid),
              normalize_guid(event_value(event, :source_guid), @unknown_source_guid),
              normalize_spell_id(event_value(event, :spell_id))
            }

            complete_defensive_window(pending, key, windows, event)

          true ->
            {windows, pending}
        end
      end)

    pending_windows =
      pending
      |> Map.values()
      |> List.flatten()

    (windows ++ pending_windows)
    |> Enum.reverse()
    |> Enum.sort_by(&{&1.started_at_ms_into_fight, &1.target_guid, &1.spell_id})
  end

  defp complete_defensive_window(pending, key, windows, event) do
    case Map.get(pending, key) do
      [window | rest] ->
        completed_window = %{
          window
          | ended_at_ms_into_fight: time_ms(event),
            duration_ms: max(time_ms(event) - window.started_at_ms_into_fight, 0)
        }

        {[completed_window | windows], update_pending(pending, key, rest)}

      _ ->
        {windows, pending}
    end
  end

  defp defensive_buff_event?(event, type) do
    event_type(event) == type and
      player_guid?(event_value(event, :target_guid)) and
      extra_value(event, :aura_type) == "BUFF" and
      MapSet.member?(
        SurvivalActions.aura_ids(),
        normalize_spell_id(event_value(event, :spell_id))
      )
  end

  defp defensive_buff_window_row(encounter_dim_id, event) do
    spell_id = normalize_spell_id(event_value(event, :spell_id))
    metadata = SurvivalActions.get_by_aura_id(spell_id)

    %{
      encounter_dim_id: encounter_dim_id,
      target_guid: normalize_guid(event_value(event, :target_guid), @unknown_target_guid),
      source_guid: normalize_guid(event_value(event, :source_guid), @unknown_source_guid),
      spell_id: spell_id,
      spell_name: event_value(event, :spell_name) || metadata.name,
      category: Atom.to_string(metadata.category),
      started_at_ms_into_fight: time_ms(event),
      ended_at_ms_into_fight: nil,
      duration_ms: nil
    }
  end

  defp project_survival_actions(encounter_dim_id, events) do
    {cast_entries, consumable_heals} =
      Enum.reduce(events, {[], []}, fn event, {casts, heals} = acc ->
        case classify_survival_event(event) do
          {:cast, action} ->
            {[{survival_cast_row(encounter_dim_id, event, action), action} | casts], heals}

          {:heal, action} ->
            {casts, [consumable_heal(event, action) | heals]}

          :ignore ->
            acc
        end
      end)

    cast_entries
    |> Enum.reverse()
    |> attach_consumable_heals(Enum.reverse(consumable_heals))
    |> Enum.sort_by(&{&1.used_at_ms_into_fight, &1.caster_guid, &1.spell_id})
  end

  defp classify_survival_event(event) do
    type = event_type(event)

    if type in ["SPELL_CAST_SUCCESS", "SPELL_HEAL"] and
         player_guid?(event_value(event, :source_guid)) do
      event
      |> event_value(:spell_id)
      |> normalize_spell_id()
      |> SurvivalActions.get_by_cast_id()
      |> case do
        nil -> :ignore
        action when type == "SPELL_CAST_SUCCESS" -> {:cast, action}
        %{category: :consumable} = action -> {:heal, action}
        _action -> :ignore
      end
    else
      :ignore
    end
  end

  defp survival_cast_row(encounter_dim_id, event, action) do
    caster_guid = normalize_guid(event_value(event, :source_guid), @unknown_source_guid)

    %{
      encounter_dim_id: encounter_dim_id,
      caster_guid: caster_guid,
      target_guid: survival_target_guid(event, caster_guid),
      spell_id: normalize_spell_id(event_value(event, :spell_id)),
      spell_name: event_value(event, :spell_name) || action.name,
      kind: Atom.to_string(action.kind),
      category: Atom.to_string(action.category),
      used_at_ms_into_fight: time_ms(event),
      heal_amount: nil,
      overheal_amount: nil
    }
  end

  # Externals are cast on other players; self-casts log a nil or non-player
  # target, so the receiver falls back to the caster.
  defp survival_target_guid(event, caster_guid) do
    target_guid = event_value(event, :target_guid)

    if player_guid?(target_guid), do: target_guid, else: caster_guid
  end

  defp consumable_heal(event, action) do
    %{
      caster_guid: normalize_guid(event_value(event, :source_guid), @unknown_source_guid),
      action_key: action.key,
      ms: time_ms(event),
      amount: non_negative_integer(event_value(event, :amount)),
      overheal: non_negative_integer(event_value(event, :overhealing))
    }
  end

  # Joins each consumable cast to the nearest unclaimed resulting SPELL_HEAL.
  # The window is symmetric: real 12.0 logs can stamp the heal a moment
  # before its own SPELL_CAST_SUCCESS line.
  defp attach_consumable_heals(cast_entries, consumable_heals) do
    {rows, _remaining_heals} =
      Enum.map_reduce(cast_entries, consumable_heals, fn {row, action}, heals ->
        case claim_consumable_heal(heals, row, action) do
          nil ->
            {row, heals}

          heal ->
            {%{row | heal_amount: heal.amount, overheal_amount: heal.overheal},
             List.delete(heals, heal)}
        end
      end)

    rows
  end

  defp claim_consumable_heal(heals, row, %{category: :consumable} = action) do
    heals
    |> Enum.filter(fn heal ->
      heal.caster_guid == row.caster_guid and heal.action_key == action.key and
        abs(heal.ms - row.used_at_ms_into_fight) <= @consumable_heal_join_window_ms
    end)
    |> Enum.min_by(&abs(&1.ms - row.used_at_ms_into_fight), fn -> nil end)
  end

  defp claim_consumable_heal(_heals, _row, _action), do: nil

  defp project_player_info(encounter_dim_id, events, tank_guids) do
    class_info = collect_class_info(events)

    events
    |> Enum.reduce(%{}, &collect_player_names/2)
    |> Map.merge(class_info, fn _guid, player, class_data -> Map.merge(player, class_data) end)
    |> Enum.map(fn {guid, data} ->
      spec_id = Map.get(data, :spec_id)
      class_id = Map.get(data, :class_id) || WowClass.class_from_spec(spec_id)

      %{
        encounter_dim_id: encounter_dim_id,
        player_guid: guid,
        player_name: Map.get(data, :player_name) || @unknown_player_name,
        class_id: class_id,
        spec_id: spec_id,
        item_level: Map.get(data, :item_level),
        detected_role: detected_role(spec_id, tank_guids, guid),
        talents: Map.get(data, :talents)
      }
    end)
    |> Enum.sort_by(& &1.player_guid)
  end

  defp detected_role(spec_id, tank_guids, guid) do
    WowClass.role_from_spec(spec_id) ||
      if(MapSet.member?(tank_guids, guid), do: "tank", else: "unknown")
  end

  defp collect_class_info(events) do
    Enum.reduce(events, %{}, fn event, acc ->
      if event_type(event) == "COMBATANT_INFO" and player_guid?(event_value(event, :source_guid)) do
        guid = event_value(event, :source_guid)
        spec_id = normalize_optional_integer(extra_value(event, :spec_id))

        class_id =
          normalize_optional_integer(extra_value(event, :class_id)) ||
            WowClass.class_from_spec(spec_id)

        item_level = normalize_optional_integer(extra_value(event, :item_level))
        talents = normalize_talent_payload(extra_value(event, :talents))

        Map.update(
          acc,
          guid,
          %{spec_id: spec_id, class_id: class_id, item_level: item_level, talents: talents},
          &merge_class_info(&1, spec_id, class_id, item_level, talents)
        )
      else
        acc
      end
    end)
  end

  defp merge_class_info(existing, spec_id, class_id, item_level, talents) do
    existing
    |> maybe_put(:spec_id, spec_id)
    |> maybe_put(:class_id, class_id)
    |> maybe_put(:item_level, item_level)
    |> maybe_put(:talents, talents)
  end

  # The native parser emits class-talent triples as [node_id, entry_id, rank];
  # persist them as self-describing maps so fresh projections match the
  # jsonb rows read back from silver. A missing payload stays nil (unknown).
  defp normalize_talent_payload(triples) when is_list(triples) do
    for [node_id, entry_id, rank] <- triples,
        is_integer(node_id) and is_integer(entry_id) and is_integer(rank) do
      %{"node_id" => node_id, "entry_id" => entry_id, "rank" => rank}
    end
  end

  defp normalize_talent_payload(_payload), do: nil

  defp collect_player_names(event, acc) do
    acc
    |> maybe_collect_player(event_value(event, :source_guid), event_value(event, :source_name))
    |> maybe_collect_player(event_value(event, :target_guid), event_value(event, :target_name))
  end

  defp maybe_collect_player(acc, guid, name) do
    if player_guid?(guid) do
      Map.update(acc, guid, %{player_name: clean_player_name(name)}, fn existing ->
        maybe_put(existing, :player_name, clean_player_name(name))
      end)
    else
      acc
    end
  end

  defp detect_tank_guids(events) do
    events
    |> Enum.filter(
      &(event_type(&1) == "SWING_DAMAGE" and player_guid?(event_value(&1, :target_guid)) and
          npc_guid?(event_value(&1, :source_guid)))
    )
    |> Enum.reduce(%{}, fn event, acc ->
      target_guid = event_value(event, :target_guid)
      amount = non_negative_integer(event_value(event, :amount))
      Map.update(acc, target_guid, amount, &(&1 + amount))
    end)
    |> Enum.sort_by(fn {_guid, amount} -> amount end, :desc)
    |> Enum.take(2)
    |> Enum.map(fn {guid, _amount} -> guid end)
    |> MapSet.new()
  end

  defp event_type(event), do: event_value(event, :type)

  defp event_value(event, key) when is_map(event) do
    Map.get(event, key) || Map.get(event, Atom.to_string(key))
  end

  defp extra_value(event, key) do
    extra = event_value(event, :extra) || %{}
    Map.get(extra, key) || Map.get(extra, Atom.to_string(key))
  end

  defp time_ms(event) do
    event
    |> event_value(:time_into_fight)
    |> case do
      value when is_integer(value) -> value * 1000
      value when is_float(value) -> round(value * 1000)
      _ -> 0
    end
  end

  defp normalize_spell_id(value) when is_integer(value), do: value
  defp normalize_spell_id(value) when is_binary(value), do: parse_integer(value) || 0
  defp normalize_spell_id(_value), do: 0

  defp normalize_optional_integer(nil), do: nil
  defp normalize_optional_integer(0), do: nil
  defp normalize_optional_integer(value) when is_integer(value), do: value
  defp normalize_optional_integer(value) when is_binary(value), do: parse_integer(value)
  defp normalize_optional_integer(_value), do: nil

  defp parse_integer(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp non_negative_integer(value) when is_integer(value) and value > 0, do: value

  defp non_negative_integer(value) when is_binary(value),
    do: value |> parse_integer() |> non_negative_integer()

  defp non_negative_integer(_value), do: 0

  defp normalize_guid(value, fallback) when is_binary(value) do
    if String.trim(value) == "", do: fallback, else: value
  end

  defp normalize_guid(_value, fallback), do: fallback

  defp player_guid?(guid) when is_binary(guid), do: String.starts_with?(guid, "Player-")
  defp player_guid?(_guid), do: false

  defp npc_guid?(guid) when is_binary(guid) do
    String.starts_with?(guid, "Creature-") or String.starts_with?(guid, "Vehicle-")
  end

  defp npc_guid?(_guid), do: false

  defp hostile_npc_source?(event) do
    hostile_npc_guid?(event_value(event, :source_guid), event_value(event, :source_flags))
  end

  defp hostile_npc_target?(event) do
    hostile_npc_guid?(event_value(event, :target_guid), event_value(event, :target_flags))
  end

  defp hostile_npc_guid?(guid, flags) when is_integer(flags) do
    npc_guid?(guid) and flag?(flags, @object_reaction_hostile) and
      not flag?(flags, @object_affiliation_group) and
      not flag?(flags, @object_reaction_friendly) and
      not flag?(flags, @object_control_player)
  end

  defp hostile_npc_guid?(guid, _flags), do: npc_guid?(guid)

  defp flag?(flags, mask), do: band(flags, mask) != 0

  defp clean_player_name(name) when is_binary(name) do
    name
    |> String.split("-")
    |> List.first()
    |> case do
      "" -> @unknown_player_name
      clean_name -> clean_name
    end
  end

  defp clean_player_name(_name), do: @unknown_player_name

  defp clean_optional_name(name) when is_binary(name) do
    name
    |> String.split("-")
    |> List.first()
    |> case do
      "" -> nil
      clean_name -> clean_name
    end
  end

  defp clean_optional_name(_name), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, @unknown_player_name), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
