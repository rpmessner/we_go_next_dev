defmodule WeGoNext.Gold.ObservedMechanics do
  @moduledoc """
  Encounter-scoped observed mechanic read model.

  This module is query-only. It starts from silver rows that actually appeared in
  imported logs, then attaches code-defined raid catalog entries, synced mechanic
  definitions, and failure facts where available.
  """

  import Ecto.Query

  alias WeGoNext.GameData.Raids.MidnightSeason1
  alias WeGoNext.GameData.{Interrupts, Spells}

  alias WeGoNext.Gold.{
    DimEncounter,
    DimMechanicCriterion,
    FactFailure
  }

  alias WeGoNext.Repo
  alias WeGoNext.Silver.{DamageTakenEvent, DebuffApplication, InterruptOpportunity}

  @type observed_row :: %{
          spell_id: integer(),
          spell_name: String.t(),
          boss_name: String.t() | nil,
          observed: map(),
          catalog: map() | nil,
          criteria: [map()],
          facts: map(),
          rule_status: atom(),
          diagnostics: [String.t()]
        }

  @type t :: %{
          encounter: DimEncounter.t(),
          mechanics: [observed_row()],
          counts: %{atom() => non_neg_integer()}
        }

  @doc """
  Returns observed mechanics for a gold encounter ID.
  """
  @spec for_encounter(pos_integer() | String.t(), keyword()) ::
          {:ok, t()} | {:error, :not_found | :invalid_id}
  def for_encounter(id, opts \\ []) do
    with {:ok, id} <- parse_id(id),
         %DimEncounter{} = encounter <- Repo.get(DimEncounter, id) do
      observed = observed_by_spell(id)
      spell_ids = observed |> Map.keys() |> Enum.sort()

      catalog = catalog_by_spell(encounter.wow_encounter_id)
      criteria = criteria_by_spell(spell_ids, encounter)
      facts = facts_by_spell(id, spell_ids)

      mechanics =
        spell_ids
        |> Enum.map(fn spell_id ->
          build_row(
            spell_id,
            encounter,
            observed,
            catalog,
            criteria,
            facts,
            opts
          )
        end)
        |> Enum.sort_by(&row_sort_key/1)

      {:ok,
       %{
         encounter: encounter,
         mechanics: mechanics,
         counts: counts(mechanics)
       }}
    else
      nil -> {:error, :not_found}
      :error -> {:error, :invalid_id}
    end
  end

  defp observed_by_spell(encounter_dim_id) do
    %{}
    |> merge_observed(damage_observations(encounter_dim_id))
    |> merge_observed(debuff_observations(encounter_dim_id))
    |> merge_observed(interrupt_observations(encounter_dim_id))
  end

  defp damage_observations(encounter_dim_id) do
    DamageTakenEvent
    |> where([row], row.encounter_dim_id == ^encounter_dim_id)
    |> group_by([row], [row.spell_id, row.spell_name])
    |> select([row], %{
      spell_id: row.spell_id,
      spell_name: row.spell_name,
      damage_hits: count(row.id),
      affected_players: count(row.target_guid, :distinct),
      source_count: count(row.source_guid, :distinct),
      total_damage: coalesce(sum(row.amount), 0),
      max_hit: coalesce(max(row.amount), 0),
      first_seen_ms: min(row.occurred_at_ms_into_fight),
      last_seen_ms: max(row.occurred_at_ms_into_fight)
    })
    |> Repo.all()
    |> Enum.map(fn row ->
      {row.spell_id,
       %{
         spell_name: row.spell_name,
         damage_hits: integer_value(row.damage_hits),
         affected_players: integer_value(row.affected_players),
         damage_source_count: integer_value(row.source_count),
         total_damage: integer_value(row.total_damage),
         max_hit: integer_value(row.max_hit),
         first_seen_ms: row.first_seen_ms,
         last_seen_ms: row.last_seen_ms
       }}
    end)
  end

  defp debuff_observations(encounter_dim_id) do
    DebuffApplication
    |> where([row], row.encounter_dim_id == ^encounter_dim_id)
    |> group_by([row], row.spell_id)
    |> select([row], %{
      spell_id: row.spell_id,
      debuff_applications: count(row.id),
      debuffed_players: count(row.target_guid, :distinct),
      max_stack_count: coalesce(max(row.stack_count), 0),
      first_seen_ms: min(row.applied_at_ms_into_fight),
      last_seen_ms: max(row.applied_at_ms_into_fight)
    })
    |> Repo.all()
    |> Enum.map(fn row ->
      {row.spell_id,
       %{
         debuff_applications: integer_value(row.debuff_applications),
         debuffed_players: integer_value(row.debuffed_players),
         max_stack_count: integer_value(row.max_stack_count),
         first_seen_ms: row.first_seen_ms,
         last_seen_ms: row.last_seen_ms
       }}
    end)
  end

  defp interrupt_observations(encounter_dim_id) do
    interrupt_spell_ids = Interrupts.spell_id_list()

    InterruptOpportunity
    |> where(
      [row],
      row.encounter_dim_id == ^encounter_dim_id and
        row.interrupted_spell_id in ^interrupt_spell_ids
    )
    |> group_by([row], row.interrupted_spell_id)
    |> select([row], %{
      spell_id: row.interrupted_spell_id,
      interrupt_opportunities: count(row.id),
      successful_interrupts: fragment("count(*) FILTER (WHERE ?)", row.success),
      missed_interrupts: fragment("count(*) FILTER (WHERE NOT ?)", row.success),
      interrupt_target_count: count(row.target_npc_guid, :distinct),
      first_seen_ms: min(row.opportunity_ms_into_fight),
      last_seen_ms: max(row.opportunity_ms_into_fight)
    })
    |> Repo.all()
    |> Enum.map(fn row ->
      {row.spell_id,
       %{
         interrupt_opportunities: integer_value(row.interrupt_opportunities),
         successful_interrupts: integer_value(row.successful_interrupts),
         missed_interrupts: integer_value(row.missed_interrupts),
         interrupt_target_count: integer_value(row.interrupt_target_count),
         first_seen_ms: row.first_seen_ms,
         last_seen_ms: row.last_seen_ms
       }}
    end)
  end

  defp merge_observed(acc, rows) do
    Enum.reduce(rows, acc, fn {spell_id, observed}, acc ->
      Map.update(
        acc,
        spell_id,
        merge_observed_values(base_observed(), observed),
        &merge_observed_values(&1, observed)
      )
    end)
  end

  defp merge_observed_values(existing, observed) do
    existing
    |> Map.merge(observed, fn
      :spell_name, nil, value ->
        value

      :spell_name, value, _other ->
        value

      key, existing_value, observed_value when key in [:first_seen_ms] ->
        min_optional(existing_value, observed_value)

      key, existing_value, observed_value when key in [:last_seen_ms] ->
        max_optional(existing_value, observed_value)

      _key, existing_value, observed_value
      when is_integer(existing_value) and is_integer(observed_value) ->
        existing_value + observed_value

      _key, _existing_value, observed_value ->
        observed_value
    end)
  end

  defp base_observed do
    %{
      spell_name: nil,
      damage_hits: 0,
      affected_players: 0,
      damage_source_count: 0,
      total_damage: 0,
      max_hit: 0,
      debuff_applications: 0,
      debuffed_players: 0,
      max_stack_count: 0,
      interrupt_opportunities: 0,
      successful_interrupts: 0,
      missed_interrupts: 0,
      interrupt_target_count: 0,
      first_seen_ms: nil,
      last_seen_ms: nil
    }
  end

  defp catalog_by_spell(wow_encounter_id) do
    MidnightSeason1.mechanics()
    |> Enum.filter(&(to_string(Map.get(&1, :boss_encounter_id)) == to_string(wow_encounter_id)))
    |> Map.new(&{&1.spell_id, catalog_entry(&1)})
  end

  defp catalog_entry(mechanic) do
    %{
      spell_id: mechanic.spell_id,
      spell_name: mechanic.name,
      mechanic_type: mechanic.type,
      event: mechanic.event,
      boss_encounter_id: mechanic.boss_encounter_id,
      boss_name: mechanic.boss_name,
      raid_name: mechanic.raid_name,
      raid_slug: mechanic.raid_slug,
      track: Map.get(mechanic, :track, true),
      rule: Map.get(mechanic, :rule, %{}),
      sources: Map.get(mechanic, :sources, []),
      notes: Map.get(mechanic, :notes)
    }
  end

  defp criteria_by_spell([], _encounter), do: %{}

  defp criteria_by_spell(spell_ids, %DimEncounter{} = encounter) do
    DimMechanicCriterion
    |> where([criterion], criterion.spell_id in ^spell_ids and criterion.active == true)
    |> where(
      [criterion],
      is_nil(criterion.boss_encounter_id) or
        criterion.boss_encounter_id == ^encounter.wow_encounter_id
    )
    |> where(
      [criterion],
      is_nil(criterion.difficulty_id) or criterion.difficulty_id == ^encounter.difficulty_id
    )
    |> order_by([criterion], asc: criterion.spell_name, asc: criterion.id)
    |> select([criterion], %{
      criterion_dim_id: criterion.id,
      spell_id: criterion.spell_id,
      spell_name: criterion.spell_name,
      mechanic_type: criterion.mechanic_type,
      boss_encounter_id: criterion.boss_encounter_id,
      boss_name: criterion.boss_name,
      difficulty_id: criterion.difficulty_id,
      threshold: criterion.threshold,
      ruleset_id: criterion.ruleset_id,
      ruleset_version: criterion.ruleset_version
    })
    |> Repo.all()
    |> Enum.group_by(& &1.spell_id)
  end

  defp facts_by_spell(_encounter_dim_id, []), do: %{}

  defp facts_by_spell(encounter_dim_id, spell_ids) do
    FactFailure
    |> join(:inner, [failure], criterion in DimMechanicCriterion,
      on: criterion.id == failure.criterion_dim_id
    )
    |> where(
      [failure, criterion],
      failure.encounter_dim_id == ^encounter_dim_id and criterion.spell_id in ^spell_ids
    )
    |> group_by([failure, criterion], criterion.spell_id)
    |> select([failure, criterion], %{
      spell_id: criterion.spell_id,
      failure_count: coalesce(sum(failure.failure_count), 0),
      total_damage: coalesce(sum(failure.total_damage), 0),
      failed_player_count: count(failure.player_dim_id, :distinct)
    })
    |> Repo.all()
    |> Map.new(fn row ->
      {row.spell_id,
       %{
         failure_count: integer_value(row.failure_count),
         total_damage: integer_value(row.total_damage),
         failed_player_count: integer_value(row.failed_player_count)
       }}
    end)
  end

  defp build_row(
         spell_id,
         encounter,
         observed,
         catalog,
         criteria,
         facts,
         opts
       ) do
    observed = Map.get(observed, spell_id, base_observed())
    catalog_entry = Map.get(catalog, spell_id)
    criteria = Map.get(criteria, spell_id, [])
    facts = Map.get(facts, spell_id, %{failure_count: 0, total_damage: 0, failed_player_count: 0})
    rule_status = rule_status(catalog_entry, criteria, facts)

    %{
      spell_id: spell_id,
      spell_name: spell_name(spell_id, observed, catalog_entry, criteria, opts),
      boss_name: (catalog_entry && catalog_entry.boss_name) || encounter.name,
      observed: observed,
      catalog: catalog_entry,
      criteria: criteria,
      facts: facts,
      rule_status: rule_status,
      diagnostics: diagnostics(rule_status, observed, catalog_entry, criteria, facts)
    }
  end

  defp spell_name(spell_id, observed, catalog, criteria, _opts) do
    cond do
      is_binary(catalog && catalog.spell_name) ->
        catalog.spell_name

      criteria != [] ->
        criteria |> List.first() |> Map.fetch!(:spell_name)

      is_binary(observed.spell_name) ->
        observed.spell_name

      is_binary(Spells.name(spell_id)) ->
        Spells.name(spell_id)

      true ->
        "Spell #{spell_id}"
    end
  end

  defp rule_status(_catalog, _criteria, %{failure_count: failure_count})
       when failure_count > 0,
       do: :producing_failures

  defp rule_status(_catalog, [_criterion | _rest], _facts),
    do: :active_criterion

  defp rule_status(%{track: true}, _criteria, _facts), do: :catalog_tracked
  defp rule_status(%{track: false}, _criteria, _facts), do: :catalog_context

  defp rule_status(_catalog, _criteria, _facts), do: :observed_only

  defp diagnostics(:producing_failures, _observed, _catalog, _criteria, _facts), do: []

  defp diagnostics(:active_criterion, _observed, _catalog, _criteria, _facts) do
    ["Tracked, but no failures were recorded for this pull."]
  end

  defp diagnostics(:catalog_tracked, _observed, _catalog, _criteria, _facts) do
    [
      "Known trackable mechanic, but tracking is not enabled for this pull yet."
    ]
  end

  defp diagnostics(:catalog_context, _observed, _catalog, _criteria, _facts) do
    [
      "Known encounter mechanic, but it is informational only and does not count as a failure."
    ]
  end

  defp diagnostics(:observed_only, _observed, _catalog, _criteria, _facts) do
    ["Seen in the combat log, but not currently recognized as a tracked mechanic."]
  end

  defp counts(mechanics) do
    %{
      observed_spells: length(mechanics),
      producing_failures: Enum.count(mechanics, &(&1.rule_status == :producing_failures)),
      active_criteria: Enum.count(mechanics, &(&1.rule_status == :active_criterion)),
      catalog_tracked: Enum.count(mechanics, &(&1.rule_status == :catalog_tracked)),
      catalog_context: Enum.count(mechanics, &(&1.rule_status == :catalog_context)),
      code_defined: Enum.count(mechanics, & &1.catalog),
      observed_only: Enum.count(mechanics, &(&1.rule_status == :observed_only))
    }
  end

  defp row_sort_key(row) do
    {
      status_rank(row.rule_status),
      -row.facts.failure_count,
      -row.observed.total_damage,
      -row.observed.damage_hits,
      String.downcase(row.spell_name || ""),
      row.spell_id
    }
  end

  defp status_rank(:producing_failures), do: 0
  defp status_rank(:active_criterion), do: 1
  defp status_rank(:catalog_tracked), do: 2
  defp status_rank(:catalog_context), do: 3
  defp status_rank(:observed_only), do: 4

  defp min_optional(nil, value), do: value
  defp min_optional(value, nil), do: value
  defp min_optional(left, right), do: min(left, right)

  defp max_optional(nil, value), do: value
  defp max_optional(value, nil), do: value
  defp max_optional(left, right), do: max(left, right)

  defp integer_value(nil), do: 0
  defp integer_value(%Decimal{} = value), do: Decimal.to_integer(value)
  defp integer_value(value) when is_integer(value), do: value

  defp parse_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _ -> :error
    end
  end

  defp parse_id(_id), do: :error
end
