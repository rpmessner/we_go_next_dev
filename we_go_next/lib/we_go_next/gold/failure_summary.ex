defmodule WeGoNext.Gold.FailureSummary do
  @moduledoc """
  Read model for cross-encounter mechanic failure summaries.
  """

  import Ecto.Query

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, FactFailure}
  alias WeGoNext.Gold.FactFailure.Derivation
  alias WeGoNext.Repo
  alias WeGoNext.Rules.{MechanicCriterion, Ruleset}
  alias WeGoNext.Silver.{DamageTaken, InterruptOpportunity}

  @default_date_range_days 14

  @type filters :: %{
          optional(:start_date) => Date.t(),
          optional(:end_date) => Date.t()
        }

  @type row :: %{
          player_dim_id: pos_integer(),
          player_guid: String.t(),
          player_name: String.t(),
          criterion_dim_id: pos_integer(),
          spell_id: integer(),
          spell_name: String.t(),
          mechanic_type: String.t(),
          boss_name: String.t() | nil,
          difficulty_id: integer() | nil,
          failure_count: non_neg_integer(),
          total_damage: non_neg_integer(),
          encounter_count: non_neg_integer(),
          latest_start_time: DateTime.t() | nil
        }

  @type diagnostic :: %{
          severity: :blocked | :warning | :info,
          title: String.t(),
          body: String.t()
        }

  @type rule_diagnostic :: %{
          severity: :blocked | :warning | :info,
          title: String.t(),
          body: String.t(),
          reason: atom(),
          rule_id: pos_integer(),
          criterion_dim_id: pos_integer() | nil,
          spell_id: integer(),
          spell_name: String.t(),
          mechanic_type: String.t(),
          boss_name: String.t() | nil,
          boss_encounter_id: String.t() | nil,
          matching_encounters_count: non_neg_integer(),
          encounter_damage_rows_count: non_neg_integer(),
          silver_damage_rows_count: non_neg_integer(),
          silver_hit_count: non_neg_integer(),
          fact_rows_count: non_neg_integer()
        }

  @type readiness :: %{
          mechanics_synced?: boolean(),
          synced_mechanics_count: non_neg_integer(),
          failure_ready_mechanics_count: non_neg_integer(),
          imported_observation_count: non_neg_integer(),
          selected_failure_row_count: non_neg_integer(),
          stale_mechanic_definition_count: non_neg_integer(),
          stale_failure_logic_count: non_neg_integer(),
          active_ruleset: Ruleset.t() | nil,
          active_authored_rules_count: non_neg_integer(),
          active_promoted_snapshots_count: non_neg_integer(),
          scoped_encounters_count: non_neg_integer(),
          selected_fact_count: non_neg_integer(),
          total_fact_count: non_neg_integer(),
          active_fact_count: non_neg_integer(),
          matching_silver_observation_count: non_neg_integer(),
          matching_criteria_count: non_neg_integer(),
          stale_fact_count: non_neg_integer(),
          stale_derivation_fact_count: non_neg_integer(),
          current_derivation_version: pos_integer(),
          latest_rebuilt_at: DateTime.t() | nil,
          zero_fact_rule_diagnostics: [rule_diagnostic()],
          diagnostics: [diagnostic()]
        }

  @doc """
  Returns the default failures date range.

  The range is anchored to the latest imported pull instead of wall
  clock time, so archived logs still produce useful defaults.
  """
  @spec default_filters() :: filters()
  def default_filters do
    DimEncounter
    |> select([encounter], max(encounter.start_time))
    |> Repo.one()
    |> case do
      %DateTime{} = latest_start_time ->
        end_date = DateTime.to_date(latest_start_time)
        %{start_date: Date.add(end_date, -(@default_date_range_days - 1)), end_date: end_date}

      _latest_start_time ->
        %{}
    end
  end

  @doc """
  Returns tracked mechanic failures grouped by player and criterion.
  """
  @spec list_grouped_failures(filters()) :: [row()]
  def list_grouped_failures(filters \\ %{}) when is_map(filters) do
    FactFailure
    |> join(:inner, [failure], player in assoc(failure, :player))
    |> join(:inner, [failure, player], criterion in assoc(failure, :criterion))
    |> join(:inner, [failure, player, criterion], encounter in assoc(failure, :encounter))
    |> apply_start_date(Map.get(filters, :start_date))
    |> apply_end_date(Map.get(filters, :end_date))
    |> group_by([failure, player, criterion, encounter], [
      player.id,
      player.player_guid,
      player.player_name,
      criterion.id,
      criterion.spell_id,
      criterion.spell_name,
      criterion.mechanic_type,
      criterion.boss_name,
      criterion.difficulty_id
    ])
    |> order_by([failure, player, criterion, encounter],
      asc: player.player_name,
      desc: fragment("sum(?)", failure.failure_count),
      asc: criterion.spell_name
    )
    |> select([failure, player, criterion, encounter], %{
      player_dim_id: player.id,
      player_guid: player.player_guid,
      player_name: player.player_name,
      criterion_dim_id: criterion.id,
      spell_id: criterion.spell_id,
      spell_name: criterion.spell_name,
      mechanic_type: criterion.mechanic_type,
      boss_name: criterion.boss_name,
      difficulty_id: criterion.difficulty_id,
      failure_count: fragment("sum(?)::integer", failure.failure_count),
      total_damage: fragment("sum(?)::bigint", failure.total_damage),
      encounter_count: fragment("count(DISTINCT ?)::integer", encounter.id),
      latest_start_time: max(encounter.start_time)
    })
    |> Repo.all()
  end

  @doc """
  Groups summary rows by player for rendering.
  """
  @spec group_by_player([row()]) :: [map()]
  def group_by_player(rows) when is_list(rows) do
    rows
    |> Enum.group_by(&{&1.player_dim_id, &1.player_guid, &1.player_name})
    |> Enum.map(fn {{player_dim_id, player_guid, player_name}, failures} ->
      %{
        player_dim_id: player_dim_id,
        player_guid: player_guid,
        player_name: player_name,
        failure_count: Enum.sum(Enum.map(failures, & &1.failure_count)),
        total_damage: Enum.sum(Enum.map(failures, & &1.total_damage)),
        failures: failures
      }
    end)
    |> Enum.sort_by(&{String.downcase(&1.player_name || ""), &1.player_guid || ""})
  end

  @doc """
  Returns readiness diagnostics for the failures page.

  The checks intentionally stay inside today's warehouse semantics: synced
  mechanics, matching supported imported observations, tracked failure presence, mechanic sync
  staleness, and failure-logic staleness.
  """
  @spec readiness(filters()) :: readiness()
  def readiness(filters \\ %{}) when is_map(filters) do
    active_ruleset = Repo.get_by(Ruleset, status: "active")
    synced_mechanics_count = active_authored_rules_count(active_ruleset)
    failure_ready_mechanics_count = active_promoted_snapshots_count(active_ruleset)
    selected_failure_row_count = selected_fact_count(filters)
    imported_observation_count = matching_silver_observation_count(active_ruleset, filters)
    stale_mechanic_definition_count = stale_fact_count(active_ruleset, filters)
    stale_failure_logic_count = stale_derivation_fact_count(filters)

    counts = %{
      mechanics_synced?: not is_nil(active_ruleset),
      synced_mechanics_count: synced_mechanics_count,
      failure_ready_mechanics_count: failure_ready_mechanics_count,
      imported_observation_count: imported_observation_count,
      selected_failure_row_count: selected_failure_row_count,
      stale_mechanic_definition_count: stale_mechanic_definition_count,
      stale_failure_logic_count: stale_failure_logic_count,
      active_ruleset: active_ruleset,
      active_authored_rules_count: synced_mechanics_count,
      active_promoted_snapshots_count: failure_ready_mechanics_count,
      scoped_encounters_count: scoped_encounters_count(filters),
      selected_fact_count: selected_failure_row_count,
      total_fact_count: Repo.aggregate(FactFailure, :count),
      active_fact_count: active_fact_count(active_ruleset, filters),
      matching_silver_observation_count: imported_observation_count,
      matching_criteria_count: matching_criteria_count(active_ruleset, filters),
      stale_fact_count: stale_mechanic_definition_count,
      stale_derivation_fact_count: stale_failure_logic_count,
      current_derivation_version: Derivation.current_version(),
      latest_rebuilt_at: latest_rebuilt_at(filters),
      zero_fact_rule_diagnostics: zero_fact_rule_diagnostics(filters)
    }

    Map.put(counts, :diagnostics, readiness_diagnostics(counts))
  end

  @doc """
  Explains active avoidable mechanics that currently produce no tracked failures.

  These diagnostics are intentionally scoped to supported fact semantics:
  avoidable criteria backed by `silver.damage_taken`.
  """
  @spec zero_fact_rule_diagnostics(filters()) :: [rule_diagnostic()]
  def zero_fact_rule_diagnostics(filters \\ %{}) when is_map(filters) do
    filters
    |> zero_fact_rule_rows()
    |> Enum.reject(&(to_integer(&1.fact_rows_count) > 0))
    |> Enum.map(&zero_fact_rule_diagnostic/1)
  end

  defp apply_start_date(query, %Date{} = date) do
    {:ok, start_at} = DateTime.new(date, ~T[00:00:00], "Etc/UTC")
    where(query, [failure, player, criterion, encounter], encounter.start_time >= ^start_at)
  end

  defp apply_start_date(query, _date), do: query

  defp apply_end_date(query, %Date{} = date) do
    {:ok, exclusive_end_at} = DateTime.new(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")

    where(
      query,
      [failure, player, criterion, encounter],
      encounter.start_time < ^exclusive_end_at
    )
  end

  defp apply_end_date(query, _date), do: query

  defp active_authored_rules_count(nil), do: 0

  defp active_authored_rules_count(%Ruleset{id: ruleset_id}) do
    MechanicCriterion
    |> where([criterion], criterion.ruleset_id == ^ruleset_id)
    |> Repo.aggregate(:count)
  end

  defp active_promoted_snapshots_count(nil), do: 0

  defp active_promoted_snapshots_count(%Ruleset{id: ruleset_id, version: version}) do
    active_criteria_query(ruleset_id, version)
    |> Repo.aggregate(:count)
  end

  defp scoped_encounters_count(filters) do
    DimEncounter
    |> apply_encounter_filters(filters)
    |> Repo.aggregate(:count)
  end

  defp selected_fact_count(filters) do
    FactFailure
    |> join(:inner, [failure], encounter in assoc(failure, :encounter))
    |> apply_fact_filters(filters)
    |> Repo.aggregate(:count)
  end

  defp active_fact_count(nil, _filters), do: 0

  defp active_fact_count(%Ruleset{id: ruleset_id, version: version}, filters) do
    FactFailure
    |> join(:inner, [failure], encounter in assoc(failure, :encounter))
    |> where([failure, encounter], failure.ruleset_id == ^ruleset_id)
    |> where([failure, encounter], failure.ruleset_version == ^version)
    |> apply_fact_filters(filters)
    |> Repo.aggregate(:count)
  end

  defp matching_silver_observation_count(nil, _filters), do: 0

  defp matching_silver_observation_count(%Ruleset{} = ruleset, filters) do
    silver_match_counts(ruleset, filters).observations
  end

  defp matching_criteria_count(nil, _filters), do: 0

  defp matching_criteria_count(%Ruleset{} = ruleset, filters) do
    silver_match_counts(ruleset, filters).criteria
  end

  defp stale_fact_count(nil, _filters), do: 0

  defp stale_fact_count(%Ruleset{id: ruleset_id, version: version}, filters) do
    FactFailure
    |> join(:inner, [failure], criterion in assoc(failure, :criterion))
    |> join(:inner, [failure, criterion], encounter in assoc(failure, :encounter))
    |> where(
      [failure, criterion, encounter],
      failure.ruleset_id != ^ruleset_id or failure.ruleset_version != ^version or
        failure.ruleset_id != criterion.ruleset_id or
        failure.ruleset_version != criterion.ruleset_version
    )
    |> apply_stale_fact_filters(filters)
    |> Repo.aggregate(:count)
  end

  defp stale_derivation_fact_count(filters) do
    FactFailure
    |> join(:inner, [failure], encounter in assoc(failure, :encounter))
    |> where(
      [failure, encounter],
      fragment("? IS DISTINCT FROM ?", failure.derivation_version, ^Derivation.current_version())
    )
    |> apply_fact_filters(filters)
    |> Repo.aggregate(:count)
  end

  defp latest_rebuilt_at(filters) do
    FactFailure
    |> join(:inner, [failure], encounter in assoc(failure, :encounter))
    |> apply_fact_filters(filters)
    |> select([failure, encounter], max(failure.rebuilt_at))
    |> Repo.one()
  end

  defp silver_match_counts(%Ruleset{id: ruleset_id, version: version}, filters) do
    avoidable = avoidable_silver_match_counts(ruleset_id, version, filters)
    interrupt = interrupt_silver_match_counts(ruleset_id, version, filters)

    %{
      observations: avoidable.observations + interrupt.observations,
      criteria: MapSet.size(MapSet.union(avoidable.criteria, interrupt.criteria))
    }
  end

  defp avoidable_silver_match_counts(ruleset_id, version, filters) do
    query =
      DamageTaken
      |> join(:inner, [damage], encounter in assoc(damage, :encounter))
      |> join(:inner, [damage, encounter], criterion in DimMechanicCriterion,
        on:
          criterion.spell_id == damage.spell_id and criterion.mechanic_type == "avoidable" and
            criterion.ruleset_id == ^ruleset_id and criterion.ruleset_version == ^version and
            criterion.active == true
      )
      |> apply_criterion_scope()
      |> apply_silver_observation_filters(filters)

    %{
      observations: Repo.aggregate(query, :count, :id),
      criteria: criterion_ids(query)
    }
  end

  defp interrupt_silver_match_counts(ruleset_id, version, filters) do
    query =
      InterruptOpportunity
      |> join(:inner, [opportunity], encounter in assoc(opportunity, :encounter))
      |> join(:inner, [opportunity, encounter], criterion in DimMechanicCriterion,
        on:
          criterion.spell_id == opportunity.interrupted_spell_id and
            criterion.mechanic_type == "interrupt" and criterion.ruleset_id == ^ruleset_id and
            criterion.ruleset_version == ^version and criterion.active == true
      )
      |> where([opportunity, encounter, criterion], opportunity.success == false)
      |> apply_criterion_scope()
      |> apply_silver_observation_filters(filters)

    %{
      observations: Repo.aggregate(query, :count, :id),
      criteria: criterion_ids(query)
    }
  end

  defp criterion_ids(query) do
    query
    |> select([observation, encounter, criterion], criterion.id)
    |> distinct(true)
    |> Repo.all()
    |> MapSet.new()
  end

  defp active_criteria_query(ruleset_id, version) do
    DimMechanicCriterion
    |> where([criterion], criterion.ruleset_id == ^ruleset_id)
    |> where([criterion], criterion.ruleset_version == ^version)
    |> where([criterion], criterion.active == true)
  end

  defp apply_criterion_scope(query) do
    where(
      query,
      [observation, encounter, criterion],
      is_nil(criterion.boss_encounter_id) or
        (criterion.boss_encounter_id == encounter.wow_encounter_id and
           (is_nil(criterion.difficulty_id) or
              criterion.difficulty_id == encounter.difficulty_id or
              (encounter.difficulty_id == 15 and criterion.difficulty_id in [14, 15]) or
              (encounter.difficulty_id == 16 and criterion.difficulty_id in [14, 15, 16]) or
              (encounter.difficulty_id not in [14, 15, 16] and
                 criterion.difficulty_id in [14, 15, 16])))
    )
  end

  defp apply_encounter_filters(query, filters) do
    query
    |> apply_encounter_start_date(Map.get(filters, :start_date))
    |> apply_encounter_end_date(Map.get(filters, :end_date))
  end

  defp apply_encounter_start_date(query, %Date{} = date) do
    {:ok, start_at} = DateTime.new(date, ~T[00:00:00], "Etc/UTC")
    where(query, [encounter], encounter.start_time >= ^start_at)
  end

  defp apply_encounter_start_date(query, _date), do: query

  defp apply_encounter_end_date(query, %Date{} = date) do
    {:ok, exclusive_end_at} = DateTime.new(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")
    where(query, [encounter], encounter.start_time < ^exclusive_end_at)
  end

  defp apply_encounter_end_date(query, _date), do: query

  defp apply_fact_filters(query, filters) do
    query
    |> apply_fact_start_date(Map.get(filters, :start_date))
    |> apply_fact_end_date(Map.get(filters, :end_date))
  end

  defp apply_fact_start_date(query, %Date{} = date) do
    {:ok, start_at} = DateTime.new(date, ~T[00:00:00], "Etc/UTC")
    where(query, [failure, encounter], encounter.start_time >= ^start_at)
  end

  defp apply_fact_start_date(query, _date), do: query

  defp apply_fact_end_date(query, %Date{} = date) do
    {:ok, exclusive_end_at} = DateTime.new(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")
    where(query, [failure, encounter], encounter.start_time < ^exclusive_end_at)
  end

  defp apply_fact_end_date(query, _date), do: query

  defp apply_stale_fact_filters(query, filters) do
    query
    |> apply_stale_fact_start_date(Map.get(filters, :start_date))
    |> apply_stale_fact_end_date(Map.get(filters, :end_date))
  end

  defp apply_stale_fact_start_date(query, %Date{} = date) do
    {:ok, start_at} = DateTime.new(date, ~T[00:00:00], "Etc/UTC")
    where(query, [failure, criterion, encounter], encounter.start_time >= ^start_at)
  end

  defp apply_stale_fact_start_date(query, _date), do: query

  defp apply_stale_fact_end_date(query, %Date{} = date) do
    {:ok, exclusive_end_at} = DateTime.new(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")
    where(query, [failure, criterion, encounter], encounter.start_time < ^exclusive_end_at)
  end

  defp apply_stale_fact_end_date(query, _date), do: query

  defp apply_silver_observation_filters(query, filters) do
    query
    |> apply_silver_start_date(Map.get(filters, :start_date))
    |> apply_silver_end_date(Map.get(filters, :end_date))
  end

  defp apply_silver_start_date(query, %Date{} = date) do
    {:ok, start_at} = DateTime.new(date, ~T[00:00:00], "Etc/UTC")
    where(query, [observation, encounter, criterion], encounter.start_time >= ^start_at)
  end

  defp apply_silver_start_date(query, _date), do: query

  defp apply_silver_end_date(query, %Date{} = date) do
    {:ok, exclusive_end_at} = DateTime.new(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")
    where(query, [observation, encounter, criterion], encounter.start_time < ^exclusive_end_at)
  end

  defp apply_silver_end_date(query, _date), do: query

  defp readiness_diagnostics(counts) do
    []
    |> maybe_no_active_ruleset(counts)
    |> maybe_no_promoted_criteria(counts)
    |> maybe_no_encounters(counts)
    |> maybe_no_matching_silver(counts)
    |> maybe_no_gold_facts(counts)
    |> maybe_stale_facts(counts)
    |> maybe_stale_derivation(counts)
    |> maybe_zero_fact_rules(counts)
    |> Enum.reverse()
  end

  defp maybe_no_active_ruleset(diagnostics, %{active_ruleset: nil}) do
    [
      %{
        severity: :blocked,
        title: "Current-tier mechanics not synced",
        body: "Sync current-tier mechanics and rebuild failures before reviewing data."
      }
      | diagnostics
    ]
  end

  defp maybe_no_active_ruleset(diagnostics, _counts), do: diagnostics

  defp maybe_no_promoted_criteria(
         diagnostics,
         %{
           active_ruleset: %Ruleset{},
           active_promoted_snapshots_count: 0
         }
       ) do
    [
      %{
        severity: :blocked,
        title: "Mechanics need sync",
        body:
          "No failure-ready mechanics are synced. Sync current-tier mechanics before rebuilding."
      }
      | diagnostics
    ]
  end

  defp maybe_no_promoted_criteria(diagnostics, _counts), do: diagnostics

  defp maybe_no_encounters(diagnostics, %{scoped_encounters_count: 0}) do
    [
      %{
        severity: :warning,
        title: "No pulls in scope",
        body: "No imported pulls match the current date range."
      }
      | diagnostics
    ]
  end

  defp maybe_no_encounters(diagnostics, _counts), do: diagnostics

  defp maybe_no_matching_silver(
         diagnostics,
         %{
           active_promoted_snapshots_count: promoted_count,
           scoped_encounters_count: encounter_count,
           matching_silver_observation_count: 0
         }
       )
       when promoted_count > 0 and encounter_count > 0 do
    [
      %{
        severity: :warning,
        title: "No matching observations",
        body: "Synced mechanics do not match supported imported observations in this date range."
      }
      | diagnostics
    ]
  end

  defp maybe_no_matching_silver(diagnostics, _counts), do: diagnostics

  defp maybe_no_gold_facts(
         diagnostics,
         %{
           selected_fact_count: 0,
           total_fact_count: total_fact_count,
           matching_silver_observation_count: silver_count
         }
       ) do
    body =
      cond do
        total_fact_count > 0 ->
          "No tracked failures match the current date range. Clear filters or rebuild/import data for this range."

        silver_count > 0 ->
          "Matching observations exist, but tracked failures have not been built yet. Rebuild failures."

        true ->
          "No tracked failures exist for the current scope."
      end

    [
      %{
        severity: :warning,
        title: "No tracked failures",
        body: body
      }
      | diagnostics
    ]
  end

  defp maybe_no_gold_facts(diagnostics, _counts), do: diagnostics

  defp maybe_stale_facts(diagnostics, %{stale_fact_count: stale_count}) when stale_count > 0 do
    [
      %{
        severity: :warning,
        title: "Facts may be stale",
        body:
          "#{stale_count} tracked failure row#{plural(stale_count)} were built before the current synced mechanics. Sync current-tier mechanics and rebuild failures."
      }
      | diagnostics
    ]
  end

  defp maybe_stale_facts(diagnostics, _counts), do: diagnostics

  defp maybe_stale_derivation(diagnostics, %{stale_derivation_fact_count: stale_count})
       when stale_count > 0 do
    [
      %{
        severity: :warning,
        title: "Failure logic changed",
        body:
          "#{stale_count} tracked failure row#{plural(stale_count)} were built before the current failure logic. Rebuild failures."
      }
      | diagnostics
    ]
  end

  defp maybe_stale_derivation(diagnostics, _counts), do: diagnostics

  defp maybe_zero_fact_rules(diagnostics, %{zero_fact_rule_diagnostics: []}), do: diagnostics

  defp maybe_zero_fact_rules(diagnostics, %{zero_fact_rule_diagnostics: rule_diagnostics}) do
    count = length(rule_diagnostics)

    [
      %{
        severity: :warning,
        title: "Some mechanics produced no failures",
        body:
          "#{count} synced avoidable mechanic#{plural(count)} produced no tracked failures. Review the diagnostics below for pull scope, imported damage, spell ID, disabled mechanic, or sync causes."
      }
      | diagnostics
    ]
  end

  defp zero_fact_rule_rows(filters) do
    {start_at, end_at} = filter_bounds(filters)

    result =
      Repo.query!(
        """
        WITH active_ruleset AS (
          SELECT id, version
          FROM rules.ruleset
          WHERE status = 'active'
          LIMIT 1
        ),
        avoidable_rules AS (
          SELECT
            rule.id AS rule_id,
            rule.spell_id,
            rule.spell_name,
            rule.mechanic_type,
            rule.boss_encounter_id,
            rule.boss_name,
            rule.difficulty_id,
            rule.threshold,
            rule.active AS rule_active,
            snapshot.id AS criterion_dim_id,
            snapshot.active AS snapshot_active,
            (
              snapshot.id IS NULL
              OR snapshot.ruleset_id IS DISTINCT FROM active_ruleset.id
              OR snapshot.ruleset_version IS DISTINCT FROM active_ruleset.version
              OR snapshot.spell_id IS DISTINCT FROM rule.spell_id
              OR snapshot.mechanic_type IS DISTINCT FROM rule.mechanic_type
              OR snapshot.boss_encounter_id IS DISTINCT FROM rule.boss_encounter_id
              OR snapshot.difficulty_id IS DISTINCT FROM rule.difficulty_id
              OR snapshot.threshold IS DISTINCT FROM rule.threshold
              OR snapshot.active IS DISTINCT FROM rule.active
            ) AS snapshot_stale
          FROM active_ruleset
          JOIN rules.mechanic_criterion rule
            ON rule.ruleset_id = active_ruleset.id
          LEFT JOIN gold.dim_mechanic_criterion snapshot
            ON snapshot.source_rule_id = rule.id
          WHERE rule.mechanic_type = 'avoidable'
        )
        SELECT
          rule.*,
          (
            SELECT count(*)
            FROM gold.dim_encounter encounter
            WHERE #{rule_encounter_match_sql("rule", "encounter")}
              AND ($1::timestamptz IS NULL OR encounter.start_time >= $1::timestamptz)
              AND ($2::timestamptz IS NULL OR encounter.start_time < $2::timestamptz)
          )::integer AS matching_encounters_count,
          (
            SELECT count(*)
            FROM silver.damage_taken damage
            JOIN gold.dim_encounter encounter
              ON encounter.id = damage.encounter_dim_id
            WHERE #{rule_encounter_match_sql("rule", "encounter")}
              AND ($1::timestamptz IS NULL OR encounter.start_time >= $1::timestamptz)
              AND ($2::timestamptz IS NULL OR encounter.start_time < $2::timestamptz)
          )::integer AS encounter_damage_rows_count,
          (
            SELECT count(*)
            FROM silver.damage_taken damage
            JOIN gold.dim_encounter encounter
              ON encounter.id = damage.encounter_dim_id
            WHERE #{rule_encounter_match_sql("rule", "encounter")}
              AND damage.spell_id = rule.spell_id
              AND ($1::timestamptz IS NULL OR encounter.start_time >= $1::timestamptz)
              AND ($2::timestamptz IS NULL OR encounter.start_time < $2::timestamptz)
          )::integer AS silver_damage_rows_count,
          (
            SELECT coalesce(sum(damage.hit_count), 0)
            FROM silver.damage_taken damage
            JOIN gold.dim_encounter encounter
              ON encounter.id = damage.encounter_dim_id
            WHERE #{rule_encounter_match_sql("rule", "encounter")}
              AND damage.spell_id = rule.spell_id
              AND ($1::timestamptz IS NULL OR encounter.start_time >= $1::timestamptz)
              AND ($2::timestamptz IS NULL OR encounter.start_time < $2::timestamptz)
          )::integer AS silver_hit_count,
          (
            SELECT coalesce(sum(damage.total_amount), 0)
            FROM silver.damage_taken damage
            JOIN gold.dim_encounter encounter
              ON encounter.id = damage.encounter_dim_id
            WHERE #{rule_encounter_match_sql("rule", "encounter")}
              AND damage.spell_id = rule.spell_id
              AND ($1::timestamptz IS NULL OR encounter.start_time >= $1::timestamptz)
              AND ($2::timestamptz IS NULL OR encounter.start_time < $2::timestamptz)
          )::bigint AS silver_total_damage,
          (
            SELECT count(*)
            FROM gold.fact_failure fact
            JOIN gold.dim_encounter encounter
              ON encounter.id = fact.encounter_dim_id
            WHERE rule.criterion_dim_id IS NOT NULL
              AND fact.criterion_dim_id = rule.criterion_dim_id
              AND ($1::timestamptz IS NULL OR encounter.start_time >= $1::timestamptz)
              AND ($2::timestamptz IS NULL OR encounter.start_time < $2::timestamptz)
          )::integer AS fact_rows_count
        FROM avoidable_rules rule
        ORDER BY rule.boss_name, rule.spell_name, rule.spell_id
        """,
        [start_at, end_at]
      )

    result.rows
    |> Enum.map(fn row ->
      result.columns
      |> Enum.map(&String.to_atom/1)
      |> Enum.zip(row)
      |> Map.new()
    end)
  end

  defp zero_fact_rule_diagnostic(row) do
    reason = zero_fact_reason(row)
    {severity, title, body} = zero_fact_message(reason, row)

    %{
      severity: severity,
      title: title,
      body: body,
      reason: reason,
      rule_id: row.rule_id,
      criterion_dim_id: row.criterion_dim_id,
      spell_id: row.spell_id,
      spell_name: row.spell_name,
      mechanic_type: row.mechanic_type,
      boss_name: row.boss_name,
      boss_encounter_id: row.boss_encounter_id,
      matching_encounters_count: to_integer(row.matching_encounters_count),
      encounter_damage_rows_count: to_integer(row.encounter_damage_rows_count),
      silver_damage_rows_count: to_integer(row.silver_damage_rows_count),
      silver_hit_count: to_integer(row.silver_hit_count),
      fact_rows_count: to_integer(row.fact_rows_count)
    }
  end

  defp zero_fact_reason(%{rule_active: false}), do: :inactive_rule
  defp zero_fact_reason(%{snapshot_active: false}), do: :inactive_rule
  defp zero_fact_reason(%{snapshot_stale: true}), do: :stale_gold_snapshot
  defp zero_fact_reason(%{matching_encounters_count: 0}), do: :no_matching_encounter
  defp zero_fact_reason(%{encounter_damage_rows_count: 0}), do: :no_silver_damage_rows
  defp zero_fact_reason(%{silver_damage_rows_count: 0}), do: :spell_id_mismatch

  defp zero_fact_reason(%{silver_hit_count: hit_count, threshold: threshold}) do
    if to_integer(hit_count) <= max_hits(threshold),
      do: :below_threshold,
      else: :gold_rebuild_needed
  end

  defp zero_fact_message(:inactive_rule, row) do
    {:info, "Disabled mechanic",
     "#{rule_label(row)} is disabled, so rebuilds should not emit tracked failures for it."}
  end

  defp zero_fact_message(:stale_gold_snapshot, row) do
    {:warning, "Mechanic sync needed",
     "#{rule_label(row)} is not in sync with the failure-ready mechanics. Sync current-tier mechanics before rebuilding."}
  end

  defp zero_fact_message(:no_matching_encounter, row) do
    {:warning, "No matching encounter",
     "#{rule_label(row)} is scoped to encounter #{row.boss_encounter_id}, but no imported pulls in the current filters match that boss and difficulty scope."}
  end

  defp zero_fact_message(:no_silver_damage_rows, row) do
    {:warning, "No imported damage rows",
     "#{rule_label(row)} has matching pulls, but those pulls have no imported damage rows in the current filters. Force reimport if observation import logic changed."}
  end

  defp zero_fact_message(:spell_id_mismatch, row) do
    {:warning, "Possible spell ID mismatch",
     "#{rule_label(row)} has matching pulls with damage rows, but none for spell #{row.spell_id}. Verify the catalog spell ID against observed combat-log damage spell IDs."}
  end

  defp zero_fact_message(:below_threshold, row) do
    {:info, "Below failure threshold",
     "#{rule_label(row)} has matching imported damage, but the observed hit count does not exceed the failure threshold."}
  end

  defp zero_fact_message(:gold_rebuild_needed, row) do
    {:warning, "Failure rebuild needed",
     "#{rule_label(row)} has matching imported damage above threshold, but no tracked failure row. Rebuild failures."}
  end

  defp rule_label(row) do
    boss =
      case row.boss_name do
        nil -> "all encounters"
        "" -> "all encounters"
        boss_name -> boss_name
      end

    "#{row.spell_name} (#{row.spell_id}) on #{boss}"
  end

  defp max_hits(%{} = threshold) do
    case Map.get(threshold, "max_hits") do
      value when is_integer(value) -> value
      _value -> 0
    end
  end

  defp max_hits(_threshold), do: 0

  defp rule_encounter_match_sql(rule_alias, encounter_alias) do
    """
    (
      #{rule_alias}.boss_encounter_id IS NULL
      OR (
        #{rule_alias}.boss_encounter_id = #{encounter_alias}.wow_encounter_id
        AND (
          #{rule_alias}.difficulty_id IS NULL
          OR #{rule_alias}.difficulty_id = #{encounter_alias}.difficulty_id
          OR (
            #{encounter_alias}.difficulty_id = 15
            AND #{rule_alias}.difficulty_id IN (14, 15)
          )
          OR (
            #{encounter_alias}.difficulty_id = 16
            AND #{rule_alias}.difficulty_id IN (14, 15, 16)
          )
          OR (
            #{encounter_alias}.difficulty_id NOT IN (14, 15, 16)
            AND #{rule_alias}.difficulty_id IN (14, 15, 16)
          )
        )
      )
    )
    """
  end

  defp filter_bounds(filters) do
    {filter_start_bound(Map.get(filters, :start_date)),
     filter_end_bound(Map.get(filters, :end_date))}
  end

  defp filter_start_bound(%Date{} = date) do
    {:ok, start_at} = DateTime.new(date, ~T[00:00:00], "Etc/UTC")
    start_at
  end

  defp filter_start_bound(_date), do: nil

  defp filter_end_bound(%Date{} = date) do
    {:ok, exclusive_end_at} = DateTime.new(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")
    exclusive_end_at
  end

  defp filter_end_bound(_date), do: nil

  defp plural(1), do: ""
  defp plural(_count), do: "s"

  defp to_integer(nil), do: 0
  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(%Decimal{} = value) do
    value
    |> Decimal.round(0)
    |> Decimal.to_integer()
  end
end
