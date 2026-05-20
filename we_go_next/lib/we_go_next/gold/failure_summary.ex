defmodule WeGoNext.Gold.FailureSummary do
  @moduledoc """
  Read model for cross-encounter mechanic failure summaries.
  """

  import Ecto.Query

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, FactFailure}
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

  @type readiness :: %{
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
          has_interrupt_criteria?: boolean(),
          diagnostics: [diagnostic()]
        }

  @doc """
  Returns the default failures date range.

  The range is anchored to the latest imported gold encounter instead of wall
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
  Returns mechanic failure facts grouped by player and criterion.
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

  The checks intentionally stay inside today's warehouse semantics. Until the
  derivation-version work lands, staleness can only be inferred from ruleset and
  current criterion snapshot mismatches.
  """
  @spec readiness(filters()) :: readiness()
  def readiness(filters \\ %{}) when is_map(filters) do
    active_ruleset = Repo.get_by(Ruleset, status: "active")

    counts = %{
      active_ruleset: active_ruleset,
      active_authored_rules_count: active_authored_rules_count(active_ruleset),
      active_promoted_snapshots_count: active_promoted_snapshots_count(active_ruleset),
      scoped_encounters_count: scoped_encounters_count(filters),
      selected_fact_count: selected_fact_count(filters),
      total_fact_count: Repo.aggregate(FactFailure, :count),
      active_fact_count: active_fact_count(active_ruleset, filters),
      matching_silver_observation_count:
        matching_silver_observation_count(active_ruleset, filters),
      matching_criteria_count: matching_criteria_count(active_ruleset, filters),
      stale_fact_count: stale_fact_count(active_ruleset, filters),
      has_interrupt_criteria?: has_interrupt_criteria?(active_ruleset)
    }

    Map.put(counts, :diagnostics, readiness_diagnostics(counts))
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

  defp has_interrupt_criteria?(nil), do: false

  defp has_interrupt_criteria?(%Ruleset{id: ruleset_id, version: version}) do
    active_criteria_query(ruleset_id, version)
    |> where([criterion], criterion.mechanic_type == "interrupt")
    |> Repo.exists?()
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
    |> maybe_interrupt_limit(counts)
    |> maybe_version_limit(counts)
    |> Enum.reverse()
  end

  defp maybe_no_active_ruleset(diagnostics, %{active_ruleset: nil}) do
    [
      %{
        severity: :blocked,
        title: "No active ruleset",
        body: "Activate a ruleset, promote it to gold snapshots, then rebuild gold facts."
      }
      | diagnostics
    ]
  end

  defp maybe_no_active_ruleset(diagnostics, _counts), do: diagnostics

  defp maybe_no_promoted_criteria(
         diagnostics,
         %{
           active_ruleset: %Ruleset{name: name, version: version},
           active_promoted_snapshots_count: 0
         }
       ) do
    [
      %{
        severity: :blocked,
        title: "No promoted criteria",
        body:
          "#{name} v#{version} is active, but it has no promoted gold criterion snapshots. Promote active rules before rebuilding."
      }
      | diagnostics
    ]
  end

  defp maybe_no_promoted_criteria(diagnostics, _counts), do: diagnostics

  defp maybe_no_encounters(diagnostics, %{scoped_encounters_count: 0}) do
    [
      %{
        severity: :warning,
        title: "No gold encounters in scope",
        body: "No imported gold encounters match the current date range."
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
        title: "No matching silver observations",
        body:
          "Active promoted criteria do not match supported silver observations in this date range."
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
          "No gold failure facts match the current date range. Clear filters or rebuild/import data for this range."

        silver_count > 0 ->
          "Matching silver observations exist, but no gold failure facts have been built yet. Rebuild gold facts."

        true ->
          "No gold failure facts exist for the current scope."
      end

    [
      %{
        severity: :warning,
        title: "No gold failure facts",
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
          "#{stale_count} fact row(s) do not match the active ruleset version or their current promoted criterion snapshot. Rebuild gold facts after promotion."
      }
      | diagnostics
    ]
  end

  defp maybe_stale_facts(diagnostics, _counts), do: diagnostics

  defp maybe_interrupt_limit(diagnostics, %{has_interrupt_criteria?: true}) do
    [
      %{
        severity: :info,
        title: "Interrupt evidence is provisional",
        body:
          "Until task #61 lands, interrupt diagnostics use broad silver interrupt-opportunity rows and should be treated as a coarse signal."
      }
      | diagnostics
    ]
  end

  defp maybe_interrupt_limit(diagnostics, _counts), do: diagnostics

  defp maybe_version_limit(diagnostics, counts) do
    if counts.selected_fact_count > 0 or counts.stale_fact_count > 0 do
      [
        %{
          severity: :info,
          title: "Builder-version staleness is not visible yet",
          body:
            "Until task #62 adds derivation version stamps, this page can detect ruleset/snapshot mismatch but not transform-code drift."
        }
        | diagnostics
      ]
    else
      diagnostics
    end
  end
end
