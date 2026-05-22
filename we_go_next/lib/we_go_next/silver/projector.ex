defmodule WeGoNext.Silver.Projector do
  @moduledoc """
  Projects normalized combat-log events into canonical silver table grains.

  The native parser owns byte scanning and event normalization. This module owns
  the Elixir/domain projection from those normalized events into medallion rows.
  """

  import Bitwise

  alias WeGoNext.GameData.{DefensiveBuffs, Interrupts}
  alias WeGoNext.Silver.Projection
  alias WeGoNext.WowClass

  @damage_taken_types ~w(SPELL_DAMAGE SPELL_PERIODIC_DAMAGE SWING_DAMAGE RANGE_DAMAGE ENVIRONMENTAL_DAMAGE)
  @damage_done_types ~w(SPELL_DAMAGE SPELL_PERIODIC_DAMAGE SWING_DAMAGE RANGE_DAMAGE)
  @death_recap_window_size 10

  @unknown_source_guid "__UNKNOWN_SOURCE_GUID__"
  @unknown_target_guid "__UNKNOWN_TARGET_GUID__"
  @unknown_player_name "__UNKNOWN_PLAYER__"
  @object_affiliation_group 0x00000007
  @object_reaction_friendly 0x00000010
  @object_reaction_hostile 0x00000040
  @object_control_player 0x00000100

  @doc """
  Returns table-shaped row lists for the silver tables.
  """
  def project(encounter_dim_id, events) when is_integer(encounter_dim_id) and is_list(events) do
    indexed_events =
      events
      |> Enum.with_index()
      |> Enum.sort_by(fn {event, index} -> {time_ms(event), index} end)

    events = Enum.map(indexed_events, &elem(&1, 0))
    tank_guids = detect_tank_guids(events)

    %Projection{
      damage_taken: project_damage_taken(encounter_dim_id, events),
      damage_taken_event: project_damage_taken_events(encounter_dim_id, indexed_events),
      damage_done: project_damage_done(encounter_dim_id, events),
      death: project_deaths(encounter_dim_id, events),
      interrupt_opportunity: project_interrupt_opportunities(encounter_dim_id, events),
      debuff_application: project_debuff_applications(encounter_dim_id, events),
      defensive_buff_window: project_defensive_buff_windows(encounter_dim_id, events),
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
    |> Enum.filter(&(event_type(&1) in @damage_taken_types))
    |> Enum.filter(&player_guid?(event_value(&1, :target_guid)))
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

  defp project_damage_done(encounter_dim_id, events) do
    events
    |> Enum.filter(&(event_type(&1) in @damage_done_types))
    |> Enum.filter(
      &(player_guid?(event_value(&1, :source_guid)) and npc_guid?(event_value(&1, :target_guid)))
    )
    |> Enum.reduce(%{}, fn event, acc ->
      source_guid = normalize_guid(event_value(event, :source_guid), @unknown_source_guid)
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

  defp project_deaths(encounter_dim_id, events) do
    {deaths, _damage_windows} =
      Enum.reduce(events, {[], %{}}, fn event, {deaths, damage_windows} ->
        cond do
          event_type(event) == "UNIT_DIED" and player_guid?(event_value(event, :target_guid)) ->
            target_guid = normalize_guid(event_value(event, :target_guid), @unknown_target_guid)
            recap = Map.get(damage_windows, target_guid, [])
            killing_blow = List.first(recap)

            death = %{
              encounter_dim_id: encounter_dim_id,
              target_guid: target_guid,
              died_at_ms_into_fight: time_ms(event),
              killing_blow_spell_id: killing_blow && killing_blow["spell_id"],
              killing_blow_source_guid: killing_blow && killing_blow["source_guid"],
              damage_recap: recap
            }

            {[death | deaths], Map.delete(damage_windows, target_guid)}

          event_type(event) in @damage_taken_types and
              player_guid?(event_value(event, :target_guid)) ->
            target_guid = normalize_guid(event_value(event, :target_guid), @unknown_target_guid)
            recap_event = death_recap_event(event)

            updated_windows =
              Map.update(damage_windows, target_guid, [recap_event], fn existing ->
                [recap_event | existing] |> Enum.take(@death_recap_window_size)
              end)

            {deaths, updated_windows}

          true ->
            {deaths, damage_windows}
        end
      end)

    deaths
    |> Enum.reverse()
    |> Enum.sort_by(& &1.died_at_ms_into_fight)
  end

  defp death_recap_event(event) do
    %{
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
          event_type(event) == "SPELL_CAST_START" and hostile_npc_source?(event) and
              MapSet.member?(interruptible_spell_ids, spell_id) ->
            pending_cast =
              %{
                target_npc_guid: source_guid,
                interrupted_spell_id: spell_id
              }

            {rows, Map.put(pending_casts, cast_key, pending_cast)}

          event_type(event) == "SPELL_INTERRUPT" and
            player_guid?(event_value(event, :source_guid)) and hostile_npc_target?(event) ->
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

          event_type(event) == "SPELL_CAST_SUCCESS" and
            hostile_npc_source?(event) and
              MapSet.member?(interruptible_spell_ids, spell_id) ->
            case Map.pop(pending_casts, cast_key) do
              {nil, pending_casts} ->
                {rows, pending_casts}

              {pending_cast, pending_casts} ->
                row =
                  pending_cast
                  |> Map.merge(%{
                    encounter_dim_id: encounter_dim_id,
                    opportunity_ms_into_fight: time_ms(event),
                    success: false,
                    interrupter_guid: nil,
                    interrupting_spell_id: nil
                  })

                {[row | rows], pending_casts}
            end

          true ->
            {rows, pending_casts}
        end
      end)

    rows
    |> Enum.reverse()
    |> Enum.sort_by(&{&1.opportunity_ms_into_fight, &1.target_npc_guid, &1.interrupted_spell_id})
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

            case Map.get(pending, key) do
              [app | rest] ->
                completed_app = %{
                  app
                  | duration_ms: max(time_ms(event) - app.applied_at_ms_into_fight, 0)
                }

                updated_pending =
                  if rest == [], do: Map.delete(pending, key), else: Map.put(pending, key, rest)

                {[completed_app | applications], updated_pending}

              _ ->
                {applications, pending}
            end

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

            case Map.get(pending, key) do
              [window | rest] ->
                completed_window = %{
                  window
                  | ended_at_ms_into_fight: time_ms(event),
                    duration_ms: max(time_ms(event) - window.started_at_ms_into_fight, 0)
                }

                updated_pending =
                  if rest == [], do: Map.delete(pending, key), else: Map.put(pending, key, rest)

                {[completed_window | windows], updated_pending}

              _ ->
                {windows, pending}
            end

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

  defp defensive_buff_event?(event, type) do
    event_type(event) == type and
      player_guid?(event_value(event, :target_guid)) and
      extra_value(event, :aura_type) == "BUFF" and
      MapSet.member?(DefensiveBuffs.ids(), normalize_spell_id(event_value(event, :spell_id)))
  end

  defp defensive_buff_window_row(encounter_dim_id, event) do
    spell_id = normalize_spell_id(event_value(event, :spell_id))
    metadata = DefensiveBuffs.get(spell_id)

    %{
      encounter_dim_id: encounter_dim_id,
      target_guid: normalize_guid(event_value(event, :target_guid), @unknown_target_guid),
      source_guid: normalize_guid(event_value(event, :source_guid), @unknown_source_guid),
      spell_id: spell_id,
      spell_name: event_value(event, :spell_name) || metadata.name,
      category: metadata.category,
      started_at_ms_into_fight: time_ms(event),
      ended_at_ms_into_fight: nil,
      duration_ms: nil
    }
  end

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
        detected_role: detected_role(spec_id, tank_guids, guid)
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

        Map.update(
          acc,
          guid,
          %{spec_id: spec_id, class_id: class_id, item_level: item_level},
          fn existing ->
            existing
            |> maybe_put(:spec_id, spec_id)
            |> maybe_put(:class_id, class_id)
            |> maybe_put(:item_level, item_level)
          end
        )
      else
        acc
      end
    end)
  end

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
    |> Enum.filter(&(event_type(&1) == "SWING_DAMAGE"))
    |> Enum.filter(
      &(player_guid?(event_value(&1, :target_guid)) and npc_guid?(event_value(&1, :source_guid)))
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

  defp npc_guid?(guid) when is_binary(guid), do: String.starts_with?(guid, "Creature-")
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
