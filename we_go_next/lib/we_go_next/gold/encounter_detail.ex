defmodule WeGoNext.Gold.EncounterDetail do
  @moduledoc """
  Medallion encounter detail read model keyed by `gold.dim_encounter.id`.

  This module must not call legacy analyzers, analyzer JSON cache output, or
  `public.mechanic_criteria`.
  """

  import Ecto.Query

  alias WeGoNext.GameData.{Interrupts, Spells}
  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer, FactFailure}
  alias WeGoNext.Repo

  alias WeGoNext.Silver.{
    DamageDone,
    DamageTaken,
    DamageTakenEvent,
    Death,
    DebuffApplication,
    DefensiveBuffWindow,
    InterruptOpportunity,
    PlayerInfo
  }

  @low_damage_warning_median_ratio 0.7
  @early_death_damage_warning_cutoff_ratio 0.7

  @type t :: %{
          encounter: DimEncounter.t(),
          counts: %{atom() => non_neg_integer()},
          roster: [PlayerInfo.t()],
          deaths: [map()],
          pull_review: %{
            damage_done: [map()],
            low_dps: [map()],
            damage_taken_spells: [map()],
            debuffs: %{boss: [map()], player: [map()], all: [map()]}
          },
          failure_preview: %{
            mechanics: [map()],
            diagnostics: [map()],
            counts: %{atom() => non_neg_integer()}
          },
          interrupt_coverage: %{
            spell_coverage: [map()],
            player_contributions: [map()]
          },
          personal_pull_summary: %{
            selected_player_guid: String.t() | nil,
            players: [map()]
          }
        }

  @doc """
  Returns a compact encounter detail shell read model for a gold encounter ID.
  """
  @spec get(pos_integer() | String.t()) :: {:ok, t()} | {:error, :not_found | :invalid_id}
  def get(id, opts \\ []) do
    with {:ok, id} <- parse_id(id),
         %DimEncounter{} = encounter <- Repo.get(DimEncounter, id) do
      roster = roster(id)

      {:ok,
       %{
         encounter: encounter,
         counts: counts(id),
         roster: roster,
         deaths: deaths(id),
         pull_review: pull_review(encounter, roster),
         failure_preview: failure_preview(id),
         interrupt_coverage: interrupt_coverage(id),
         personal_pull_summary:
           personal_pull_summary(encounter, roster, Keyword.get(opts, :character_name))
       }}
    else
      nil -> {:error, :not_found}
      :error -> {:error, :invalid_id}
    end
  end

  defp counts(encounter_dim_id) do
    %{
      damage_taken_groups: count(DamageTaken, encounter_dim_id),
      damage_taken_events: count(DamageTakenEvent, encounter_dim_id),
      damage_done_groups: count(DamageDone, encounter_dim_id),
      deaths: count(Death, encounter_dim_id),
      interrupt_opportunities: count_current_interrupt_opportunities(encounter_dim_id),
      debuff_applications: count(DebuffApplication, encounter_dim_id),
      defensive_buff_windows: count(DefensiveBuffWindow, encounter_dim_id),
      players: count(PlayerInfo, encounter_dim_id),
      failure_facts: count(FactFailure, encounter_dim_id)
    }
  end

  defp count(schema, encounter_dim_id) do
    schema
    |> where([row], row.encounter_dim_id == ^encounter_dim_id)
    |> Repo.aggregate(:count)
  end

  defp count_current_interrupt_opportunities(encounter_dim_id) do
    interrupt_spell_ids = Interrupts.spell_id_list()

    InterruptOpportunity
    |> where(
      [row],
      row.encounter_dim_id == ^encounter_dim_id and
        row.interrupted_spell_id in ^interrupt_spell_ids
    )
    |> Repo.aggregate(:count)
  end

  defp roster(encounter_dim_id) do
    PlayerInfo
    |> where([player], player.encounter_dim_id == ^encounter_dim_id)
    |> order_by([player], asc: player.player_name, asc: player.player_guid)
    |> Repo.all()
    |> Enum.sort_by(&{role_rank(&1.detected_role), String.downcase(&1.player_name || "")})
  end

  defp role_rank("tank"), do: 0
  defp role_rank("healer"), do: 1
  defp role_rank("dps"), do: 2
  defp role_rank(_role), do: 3

  defp deaths(encounter_dim_id) do
    Death
    |> join(:inner, [death], encounter in DimEncounter,
      on: encounter.id == death.encounter_dim_id
    )
    |> join(:left, [death, encounter], player in PlayerInfo,
      on:
        player.encounter_dim_id == death.encounter_dim_id and
          player.player_guid == death.target_guid
    )
    |> where([death, encounter, player], encounter.id == ^encounter_dim_id)
    |> order_by([death, encounter, player],
      asc: death.died_at_ms_into_fight,
      asc: death.target_guid
    )
    |> select([death, encounter, player], %{
      id: death.id,
      target_guid: death.target_guid,
      player_name: player.player_name,
      class_id: player.class_id,
      spec_id: player.spec_id,
      detected_role: player.detected_role,
      died_at_ms_into_fight: death.died_at_ms_into_fight,
      killing_blow_spell_id: death.killing_blow_spell_id,
      killing_blow_source_guid: death.killing_blow_source_guid,
      damage_recap: death.damage_recap,
      encounter_name: encounter.name
    })
    |> Repo.all()
    |> Enum.map(&Map.put(&1, :killing_blow, killing_blow(&1)))
  end

  defp killing_blow(%{damage_recap: [first | _rest]}), do: first
  defp killing_blow(_death), do: nil

  defp failure_preview(encounter_dim_id) do
    rows =
      FactFailure
      |> join(:inner, [failure], criterion in assoc(failure, :criterion))
      |> join(:inner, [failure, criterion], player in assoc(failure, :player))
      |> join(:left, [failure, criterion, player], player_info in PlayerInfo,
        on:
          player_info.encounter_dim_id == failure.encounter_dim_id and
            player_info.player_guid == player.player_guid
      )
      |> where(
        [failure, criterion, player, player_info],
        failure.encounter_dim_id == ^encounter_dim_id
      )
      |> order_by([failure, criterion, player, player_info],
        asc: criterion.boss_name,
        asc: criterion.spell_name,
        desc: failure.failure_count,
        desc: failure.total_damage,
        asc: player.player_name
      )
      |> select([failure, criterion, player, player_info], %{
        criterion_dim_id: criterion.id,
        spell_id: criterion.spell_id,
        spell_name: criterion.spell_name,
        mechanic_type: criterion.mechanic_type,
        boss_name: criterion.boss_name,
        player_dim_id: player.id,
        player_guid: player.player_guid,
        player_name: player.player_name,
        class_id: coalesce(player_info.class_id, player.class_id),
        spec_id: coalesce(player_info.spec_id, player.spec_id),
        detected_role: player_info.detected_role,
        failure_count: failure.failure_count,
        total_damage: failure.total_damage
      })
      |> Repo.all()

    mechanics =
      rows
      |> group_failure_preview_rows()
      |> attach_targeted_cone_details(encounter_dim_id)

    %{
      mechanics: mechanics,
      diagnostics: failure_preview_diagnostics(encounter_dim_id, mechanics),
      counts: %{
        mechanics: length(mechanics),
        players:
          rows
          |> Enum.map(& &1.player_guid)
          |> Enum.uniq()
          |> length(),
        failures: rows |> Enum.map(&integer_value(&1.failure_count)) |> Enum.sum(),
        damage: rows |> Enum.map(&integer_value(&1.total_damage)) |> Enum.sum()
      }
    }
  end

  defp group_failure_preview_rows(rows) do
    rows
    |> Enum.group_by(& &1.criterion_dim_id)
    |> Enum.map(fn {_criterion_dim_id, rows} ->
      first = List.first(rows)

      %{
        criterion_dim_id: first.criterion_dim_id,
        spell_id: first.spell_id,
        spell_name: first.spell_name,
        mechanic_type: first.mechanic_type,
        boss_name: first.boss_name,
        failure_count: rows |> Enum.map(&integer_value(&1.failure_count)) |> Enum.sum(),
        total_damage: rows |> Enum.map(&integer_value(&1.total_damage)) |> Enum.sum(),
        player_count: length(rows),
        players:
          Enum.map(rows, fn row ->
            %{
              player_dim_id: row.player_dim_id,
              player_guid: row.player_guid,
              player_name: row.player_name,
              class_id: row.class_id,
              spec_id: row.spec_id,
              detected_role: row.detected_role,
              failure_count: integer_value(row.failure_count),
              total_damage: integer_value(row.total_damage)
            }
          end)
      }
    end)
    |> Enum.sort_by(&{-&1.failure_count, &1.spell_name, &1.spell_id})
  end

  defp attach_targeted_cone_details(mechanics, encounter_dim_id) do
    criterion_ids =
      mechanics
      |> Enum.filter(&(&1.mechanic_type == "targeted_cone"))
      |> Enum.map(& &1.criterion_dim_id)

    contexts = targeted_cone_contexts(encounter_dim_id, criterion_ids)

    Enum.map(mechanics, fn mechanic ->
      if mechanic.mechanic_type == "targeted_cone" do
        Map.put(mechanic, :targeted_cone_events, Map.get(contexts, mechanic.criterion_dim_id, []))
      else
        mechanic
      end
    end)
  end

  defp targeted_cone_contexts(_encounter_dim_id, []), do: %{}

  defp targeted_cone_contexts(encounter_dim_id, criterion_ids) do
    sql = """
    WITH targeted_cone_markers AS (
      SELECT
        marker.encounter_dim_id,
        criterion.id AS criterion_dim_id,
        marker.target_guid,
        marker.applied_at_ms_into_fight AS marker_ms,
        target_info.player_name AS target_name,
        COALESCE(
          lead(marker.applied_at_ms_into_fight) OVER (
            PARTITION BY marker.encounter_dim_id, criterion.id
            ORDER BY marker.applied_at_ms_into_fight, marker.target_guid
          ),
          marker.applied_at_ms_into_fight + 15000
        ) AS next_marker_ms,
        criterion.threshold,
        CASE
          WHEN COALESCE(criterion.threshold->>'max_safe_hit_count', '') ~ '^[0-9]+$'
            THEN (criterion.threshold->>'max_safe_hit_count')::integer
          ELSE 0
        END AS max_safe_hit_count,
        ARRAY(
          SELECT jsonb_array_elements_text(
            COALESCE(criterion.threshold->'allowed_collateral_roles', '[]'::jsonb)
          )
        ) AS allowed_collateral_roles
      FROM silver.debuff_application marker
      JOIN gold.dim_mechanic_criterion criterion
        ON criterion.id = ANY($2::bigint[])
       AND criterion.mechanic_type = 'targeted_cone'
       AND marker.spell_id = (criterion.threshold->>'target_marker_spell_id')::integer
      LEFT JOIN silver.player_info target_info
        ON target_info.encounter_dim_id = marker.encounter_dim_id
       AND target_info.player_guid = marker.target_guid
      WHERE marker.encounter_dim_id = $1
    ),
    targeted_cone_hit_rows AS (
      SELECT
        marker.encounter_dim_id,
        marker.criterion_dim_id,
        marker.target_guid AS assigned_target_guid,
        marker.target_name AS assigned_target_name,
        marker.marker_ms,
        marker.max_safe_hit_count,
        marker.allowed_collateral_roles,
        hit.target_guid AS hit_target_guid,
        COALESCE(pi.player_name, hit.target_name) AS hit_player_name,
        COALESCE(pi.detected_role, 'unknown') AS hit_role,
        hit.amount::bigint AS damage_amount
      FROM targeted_cone_markers marker
      JOIN silver.damage_taken_event hit
        ON hit.encounter_dim_id = marker.encounter_dim_id
       AND hit.spell_id IN (
         SELECT jsonb_array_elements_text(marker.threshold->'impact_spell_ids')::integer
       )
       AND hit.occurred_at_ms_into_fight >= marker.marker_ms
       AND hit.occurred_at_ms_into_fight < marker.next_marker_ms
      LEFT JOIN silver.player_info pi
        ON pi.encounter_dim_id = hit.encounter_dim_id
       AND pi.player_guid = hit.target_guid

      UNION ALL

      SELECT
        marker.encounter_dim_id,
        marker.criterion_dim_id,
        marker.target_guid AS assigned_target_guid,
        marker.target_name AS assigned_target_name,
        marker.marker_ms,
        marker.max_safe_hit_count,
        marker.allowed_collateral_roles,
        debuff.target_guid AS hit_target_guid,
        pi.player_name AS hit_player_name,
        COALESCE(pi.detected_role, 'unknown') AS hit_role,
        0::bigint AS damage_amount
      FROM targeted_cone_markers marker
      JOIN silver.debuff_application debuff
        ON debuff.encounter_dim_id = marker.encounter_dim_id
       AND debuff.spell_id IN (
         SELECT jsonb_array_elements_text(
           COALESCE(marker.threshold->'hit_debuff_spell_ids', '[]'::jsonb)
         )::integer
       )
       AND debuff.applied_at_ms_into_fight >= marker.marker_ms
       AND debuff.applied_at_ms_into_fight < marker.next_marker_ms
      LEFT JOIN silver.player_info pi
        ON pi.encounter_dim_id = debuff.encounter_dim_id
       AND pi.player_guid = debuff.target_guid
    ),
    hit_players AS (
      SELECT
        criterion_dim_id,
        marker_ms,
        hit_target_guid,
        max(hit_player_name) AS hit_player_name,
        max(hit_role) AS hit_role,
        sum(damage_amount)::bigint AS damage_amount
      FROM targeted_cone_hit_rows
      GROUP BY criterion_dim_id, marker_ms, hit_target_guid
    ),
    cone_events AS (
      SELECT
        rows.criterion_dim_id,
        rows.assigned_target_guid,
        max(rows.assigned_target_name) AS assigned_target_name,
        rows.marker_ms,
        max(rows.max_safe_hit_count) AS max_safe_hit_count,
        count(DISTINCT rows.hit_target_guid)::integer AS hit_count,
        count(DISTINCT rows.hit_target_guid) FILTER (
          WHERE rows.hit_target_guid <> rows.assigned_target_guid
            AND NOT (rows.hit_role = ANY(rows.allowed_collateral_roles))
        )::integer AS collateral_count,
        sum(rows.damage_amount)::bigint AS total_damage
      FROM targeted_cone_hit_rows rows
      GROUP BY
        rows.criterion_dim_id,
        rows.assigned_target_guid,
        rows.marker_ms,
        rows.allowed_collateral_roles
    )
    SELECT
      event.criterion_dim_id,
      event.assigned_target_guid,
      event.assigned_target_name,
      event.marker_ms,
      event.hit_count,
      event.collateral_count,
      event.total_damage,
      'medium' AS confidence,
      jsonb_agg(
        jsonb_build_object(
          'player_guid', hit.hit_target_guid,
          'player_name', hit.hit_player_name,
          'detected_role', hit.hit_role,
          'total_damage', hit.damage_amount
        )
        ORDER BY hit.damage_amount DESC, hit.hit_player_name, hit.hit_target_guid
      ) AS hit_players
    FROM cone_events event
    JOIN hit_players hit
      ON hit.criterion_dim_id = event.criterion_dim_id
     AND hit.marker_ms = event.marker_ms
    WHERE GREATEST(event.hit_count, event.collateral_count) > event.max_safe_hit_count
    GROUP BY
      event.criterion_dim_id,
      event.assigned_target_guid,
      event.assigned_target_name,
      event.marker_ms,
      event.hit_count,
      event.collateral_count,
      event.total_damage
    ORDER BY event.marker_ms
    """

    %{rows: rows} = Repo.query!(sql, [encounter_dim_id, criterion_ids])

    rows
    |> Enum.map(fn [
                     criterion_dim_id,
                     target_guid,
                     target_name,
                     marker_ms,
                     hit_count,
                     collateral_count,
                     total_damage,
                     confidence,
                     hit_players
                   ] ->
      %{
        criterion_dim_id: criterion_dim_id,
        target_guid: target_guid,
        target_name: target_name,
        marker_ms: marker_ms,
        hit_count: hit_count,
        collateral_count: collateral_count,
        total_damage: total_damage,
        confidence: confidence,
        hit_players: normalize_jsonb_list(hit_players)
      }
    end)
    |> Enum.group_by(& &1.criterion_dim_id)
  end

  defp normalize_jsonb_list(values) when is_list(values), do: values
  defp normalize_jsonb_list(_values), do: []

  defp failure_preview_diagnostics(_encounter_dim_id, [_mechanic | _mechanics]), do: []

  defp failure_preview_diagnostics(encounter_dim_id, []) do
    encounter = Repo.get!(DimEncounter, encounter_dim_id)
    active_mechanics = active_mechanic_count(encounter)
    damage_rows = count(DamageTaken, encounter_dim_id)

    cond do
      active_mechanics == 0 ->
        [
          %{
            severity: :blocked,
            title: "No mechanic definitions found",
            body: "Add code-defined mechanics for this encounter before reviewing failures."
          }
        ]

      damage_rows == 0 ->
        [
          %{
            severity: :warning,
            title: "No player damage rows",
            body: "This pull has no imported player damage taken rows."
          }
        ]

      true ->
        [
          %{
            severity: :info,
            title: "No matched failures",
            body:
              "Damage rows exist, but none matched avoidable mechanics for this encounter. This can mean the pull was clean for supported mechanics or the catalog spell IDs do not match the log."
          }
        ]
    end
  end

  defp pull_review(%DimEncounter{} = encounter, roster) do
    damage_done = damage_done_meter(encounter, roster)

    %{
      damage_done: damage_done,
      low_dps: low_dps_players(damage_done),
      damage_taken_spells: damage_taken_spells(encounter.id),
      debuffs: debuffs(encounter.id)
    }
  end

  defp damage_done_meter(%DimEncounter{} = encounter, roster) do
    death_summaries =
      Death
      |> where([death], death.encounter_dim_id == ^encounter.id)
      |> group_by([death], death.target_guid)
      |> select([death], %{
        target_guid: death.target_guid,
        death_count: count(death.id),
        first_death_ms: min(death.died_at_ms_into_fight)
      })
      |> Repo.all()
      |> Map.new(fn row ->
        {row.target_guid,
         %{
           death_count: integer_value(row.death_count),
           first_death_ms: nullable_integer_value(row.first_death_ms)
         }}
      end)

    totals =
      DamageDone
      |> where([damage], damage.encounter_dim_id == ^encounter.id)
      |> group_by([damage], damage.source_guid)
      |> select([damage], %{
        source_guid: damage.source_guid,
        total_damage: coalesce(sum(damage.total_amount), 0),
        hit_count: coalesce(sum(damage.hit_count), 0),
        max_hit: coalesce(max(damage.max_hit), 0)
      })
      |> Repo.all()
      |> Map.new(fn row -> {row.source_guid, row} end)

    fight_seconds = max(div(integer_value(encounter.fight_time_ms), 1000), 1)

    roster
    |> Enum.map(fn player ->
      total = Map.get(totals, player.player_guid)
      death_summary = Map.get(death_summaries, player.player_guid, %{})
      total_damage = integer_value(total && total.total_damage)
      first_death_ms = Map.get(death_summary, :first_death_ms)

      %{
        player_guid: player.player_guid,
        player_name: player.player_name,
        class_id: player.class_id,
        spec_id: player.spec_id,
        detected_role: player.detected_role,
        total_damage: total_damage,
        dps: div(total_damage, fight_seconds),
        hit_count: integer_value(total && total.hit_count),
        max_hit: integer_value(total && total.max_hit),
        death_count: Map.get(death_summary, :death_count, 0),
        first_death_ms: first_death_ms,
        early_death: early_death_for_damage_warning?(first_death_ms, encounter.fight_time_ms)
      }
    end)
    |> Enum.sort_by(&{-&1.total_damage, role_rank(&1.detected_role), &1.player_name || ""})
  end

  defp low_dps_players(damage_done) do
    eligible =
      Enum.filter(damage_done, fn player ->
        player.detected_role in ["dps", "healer"] and not player.early_death and player.dps > 0
      end)

    median = median(Enum.map(eligible, & &1.dps))

    if median > 0 do
      eligible
      |> Enum.filter(&(&1.dps < median * @low_damage_warning_median_ratio))
      |> Enum.map(&Map.put(&1, :percent_of_median, Float.round(&1.dps / median * 100, 1)))
      |> Enum.sort_by(& &1.dps)
    else
      []
    end
  end

  defp early_death_for_damage_warning?(nil, _fight_time_ms), do: false

  defp early_death_for_damage_warning?(first_death_ms, fight_time_ms) do
    first_death_ms < integer_value(fight_time_ms) * @early_death_damage_warning_cutoff_ratio
  end

  defp median([]), do: 0

  defp median(values) do
    sorted = Enum.sort(values)
    count = length(sorted)
    middle = div(count, 2)

    if rem(count, 2) == 1 do
      Enum.at(sorted, middle)
    else
      (Enum.at(sorted, middle - 1) + Enum.at(sorted, middle)) / 2
    end
  end

  defp damage_taken_spells(encounter_dim_id) do
    DamageTakenEvent
    |> where([event], event.encounter_dim_id == ^encounter_dim_id)
    |> group_by([event], [event.spell_id, event.spell_name])
    |> select([event], %{
      spell_id: event.spell_id,
      spell_name: event.spell_name,
      total_damage: coalesce(sum(event.amount), 0),
      hits: count(event.id),
      players_hit: count(event.target_guid, :distinct),
      max_hit: coalesce(max(event.amount), 0),
      first_seen_ms: min(event.occurred_at_ms_into_fight)
    })
    |> Repo.all()
    |> Enum.map(fn row ->
      row
      |> Map.update!(:total_damage, &integer_value/1)
      |> Map.update!(:hits, &integer_value/1)
      |> Map.update!(:players_hit, &integer_value/1)
      |> Map.update!(:max_hit, &integer_value/1)
      |> Map.update!(:spell_name, fn name -> name || spell_name(row.spell_id) end)
    end)
    |> Enum.sort_by(&{-&1.total_damage, &1.spell_name || "", &1.spell_id || 0})
  end

  defp debuffs(encounter_dim_id) do
    rows =
      DebuffApplication
      |> where([debuff], debuff.encounter_dim_id == ^encounter_dim_id)
      |> group_by([debuff], [debuff.spell_id, debuff.source_guid])
      |> select([debuff], %{
        spell_id: debuff.spell_id,
        source_guid: debuff.source_guid,
        applications: count(debuff.id),
        players_hit: count(debuff.target_guid, :distinct),
        max_stack_count: coalesce(max(debuff.stack_count), 0),
        first_seen_ms: min(debuff.applied_at_ms_into_fight)
      })
      |> Repo.all()
      |> Enum.map(fn row ->
        row
        |> Map.put(:spell_name, spell_name(row.spell_id))
        |> Map.put(:source_type, debuff_source_type(row.source_guid))
        |> Map.update!(:applications, &integer_value/1)
        |> Map.update!(:players_hit, &integer_value/1)
        |> Map.update!(:max_stack_count, &integer_value/1)
      end)
      |> Enum.sort_by(&{-&1.applications, &1.spell_name || "", &1.spell_id || 0})

    %{
      all: rows,
      boss: Enum.reject(rows, &(&1.source_type == :player)),
      player: Enum.filter(rows, &(&1.source_type == :player))
    }
  end

  defp debuff_source_type("Player-" <> _rest), do: :player
  defp debuff_source_type(_source_guid), do: :encounter

  defp active_mechanic_count(%DimEncounter{} = encounter) do
    wow_encounter_id = encounter.wow_encounter_id
    difficulty_id = encounter.difficulty_id

    DimMechanicCriterion
    |> where([criterion], criterion.active == true)
    |> where(
      [criterion],
      is_nil(criterion.boss_encounter_id) or
        (criterion.boss_encounter_id == ^wow_encounter_id and
           (is_nil(criterion.difficulty_id) or
              criterion.difficulty_id == ^difficulty_id or
              (^difficulty_id == 15 and criterion.difficulty_id in [14, 15]) or
              (^difficulty_id == 16 and criterion.difficulty_id in [14, 15, 16]) or
              (^difficulty_id not in [14, 15, 16] and
                 criterion.difficulty_id in [14, 15, 16])))
    )
    |> Repo.aggregate(:count)
  end

  defp interrupt_coverage(encounter_dim_id) do
    rule_failures = interrupt_rule_failures(encounter_dim_id)
    visible_spell_ids = visible_interrupt_spell_ids(rule_failures)

    %{
      spell_coverage:
        interrupt_spell_coverage(encounter_dim_id, rule_failures, visible_spell_ids),
      player_contributions: interrupt_player_contributions(encounter_dim_id, visible_spell_ids)
    }
  end

  defp visible_interrupt_spell_ids(rule_failures) do
    Interrupts.spell_id_list()
    |> Kernel.++(Map.keys(rule_failures))
    |> Enum.uniq()
  end

  defp interrupt_rule_failures(encounter_dim_id) do
    FactFailure
    |> join(:inner, [failure], criterion in DimMechanicCriterion,
      on: criterion.id == failure.criterion_dim_id
    )
    |> where(
      [failure, criterion],
      failure.encounter_dim_id == ^encounter_dim_id and criterion.mechanic_type == "interrupt"
    )
    |> select([failure, criterion], %{
      spell_id: criterion.spell_id,
      spell_name: criterion.spell_name,
      criterion_dim_id: criterion.id,
      failure_count: failure.failure_count
    })
    |> Repo.all()
    |> Enum.group_by(& &1.spell_id)
    |> Map.new(fn {spell_id, rows} ->
      {spell_id,
       %{
         spell_name: rows |> List.first() |> Map.fetch!(:spell_name),
         criterion_dim_ids: Enum.map(rows, & &1.criterion_dim_id),
         failure_count: Enum.sum(Enum.map(rows, & &1.failure_count))
       }}
    end)
  end

  defp interrupt_spell_coverage(encounter_dim_id, rule_failures, visible_spell_ids) do
    InterruptOpportunity
    |> where(
      [row],
      row.encounter_dim_id == ^encounter_dim_id and row.interrupted_spell_id in ^visible_spell_ids
    )
    |> select([row], %{
      interrupted_spell_id: row.interrupted_spell_id,
      success: row.success,
      target_npc_guid: row.target_npc_guid
    })
    |> Repo.all()
    |> Enum.group_by(& &1.interrupted_spell_id)
    |> Enum.map(fn {spell_id, rows} ->
      rule_failure = Map.get(rule_failures, spell_id)
      successes = Enum.count(rows, & &1.success)
      misses = length(rows) - successes

      %{
        spell_id: spell_id,
        spell_name: spell_name(spell_id, rule_failure),
        total_opportunities: length(rows),
        successful_interrupts: successes,
        missed_casts: misses,
        target_count: rows |> Enum.map(& &1.target_npc_guid) |> Enum.uniq() |> length(),
        required_failure_count: rule_failure && rule_failure.failure_count,
        criterion_dim_ids: rule_failure && rule_failure.criterion_dim_ids
      }
    end)
    |> Enum.sort_by(&{-&1.total_opportunities, &1.spell_name, &1.spell_id})
  end

  defp interrupt_player_contributions(encounter_dim_id, visible_spell_ids) do
    InterruptOpportunity
    |> join(:left, [row], player in PlayerInfo,
      on:
        player.encounter_dim_id == row.encounter_dim_id and
          player.player_guid == row.interrupter_guid
    )
    |> where(
      [row, player],
      row.encounter_dim_id == ^encounter_dim_id and row.success == true and
        not is_nil(row.interrupter_guid) and row.interrupted_spell_id in ^visible_spell_ids
    )
    |> select([row, player], %{
      interrupter_guid: row.interrupter_guid,
      interrupted_spell_id: row.interrupted_spell_id,
      interrupting_spell_id: row.interrupting_spell_id,
      player_name: player.player_name,
      class_id: player.class_id,
      spec_id: player.spec_id,
      detected_role: player.detected_role
    })
    |> Repo.all()
    |> Enum.group_by(& &1.interrupter_guid)
    |> Enum.map(fn {guid, rows} ->
      first = List.first(rows)

      %{
        interrupter_guid: guid,
        player_name: first.player_name,
        class_id: first.class_id,
        spec_id: first.spec_id,
        detected_role: first.detected_role,
        total_interrupts: length(rows),
        interrupted_spell_count:
          rows |> Enum.map(& &1.interrupted_spell_id) |> Enum.uniq() |> length(),
        by_spell: interrupt_player_spell_counts(rows)
      }
    end)
    |> Enum.sort_by(
      &{-&1.total_interrupts, String.downcase(&1.player_name || ""), &1.interrupter_guid}
    )
  end

  defp interrupt_player_spell_counts(rows) do
    rows
    |> Enum.group_by(& &1.interrupted_spell_id)
    |> Enum.map(fn {spell_id, spell_rows} ->
      %{
        spell_id: spell_id,
        spell_name: spell_name(spell_id),
        count: length(spell_rows)
      }
    end)
    |> Enum.sort_by(&{-&1.count, &1.spell_name, &1.spell_id})
  end

  defp spell_name(spell_id, rule_failure \\ nil)

  defp spell_name(_spell_id, %{spell_name: spell_name}) when is_binary(spell_name), do: spell_name

  defp spell_name(spell_id, _rule_failure), do: Spells.name(spell_id)

  defp personal_pull_summary(%DimEncounter{} = encounter, roster, preferred_character_name) do
    players =
      roster
      |> Enum.map(fn player ->
        Map.merge(
          %{
            player_guid: player.player_guid,
            player_name: player.player_name,
            class_id: player.class_id,
            spec_id: player.spec_id,
            detected_role: player.detected_role
          },
          personal_totals(encounter.id, player.player_guid)
        )
        |> Map.put(:performance, player_encounter_performance(encounter, player.player_guid))
        |> Map.put(:defensive_analysis, defensive_analysis(encounter.id, player.player_guid))
      end)
      |> Enum.sort_by(&{role_rank(&1.detected_role), String.downcase(&1.player_name || "")})

    %{
      selected_player_guid: selected_personal_player_guid(players, preferred_character_name),
      players: players
    }
  end

  defp player_encounter_performance(%DimEncounter{} = current_encounter, player_guid) do
    pulls = player_performance_pulls(current_encounter, player_guid)

    %{
      pulls: pulls,
      summary: player_performance_summary(pulls, current_encounter.id)
    }
  end

  defp player_performance_pulls(%DimEncounter{} = current_encounter, player_guid) do
    PlayerInfo
    |> join(:inner, [player], encounter in DimEncounter,
      on: encounter.id == player.encounter_dim_id
    )
    |> where([player, encounter], player.player_guid == ^player_guid)
    |> where(
      [player, encounter],
      encounter.wow_encounter_id == ^current_encounter.wow_encounter_id and
        encounter.difficulty_id == ^current_encounter.difficulty_id
    )
    |> apply_current_or_prior_encounters(current_encounter)
    |> order_by([player, encounter], desc: encounter.start_time, desc: encounter.id)
    |> limit(8)
    |> select([player, encounter], %{
      encounter_dim_id: encounter.id,
      encounter_name: encounter.name,
      difficulty_name: encounter.difficulty_name,
      start_time: encounter.start_time,
      success: encounter.success,
      fight_time_ms: encounter.fight_time_ms,
      player_name: player.player_name,
      class_id: player.class_id,
      spec_id: player.spec_id,
      detected_role: player.detected_role
    })
    |> Repo.all()
    |> Enum.map(fn pull ->
      pull
      |> Map.put(:current, pull.encounter_dim_id == current_encounter.id)
      |> Map.merge(personal_totals(pull.encounter_dim_id, player_guid))
    end)
  end

  defp apply_current_or_prior_encounters(query, %DimEncounter{
         start_time: %DateTime{} = start_time
       }) do
    where(query, [player, encounter], encounter.start_time <= ^start_time)
  end

  defp apply_current_or_prior_encounters(query, _current_encounter), do: query

  defp player_performance_summary(pulls, current_encounter_id) do
    current_pull = Enum.find(pulls, &(&1.encounter_dim_id == current_encounter_id))
    previous_pull = previous_performance_pull(pulls, current_encounter_id)
    pull_count = length(pulls)
    total_failures = pulls |> Enum.map(& &1.mechanic_failures) |> Enum.sum()
    total_deaths = pulls |> Enum.map(& &1.death_count) |> Enum.sum()
    total_damage_taken = pulls |> Enum.map(& &1.damage_taken) |> Enum.sum()

    %{
      pull_count: pull_count,
      kill_count: Enum.count(pulls, & &1.success),
      wipe_count: Enum.count(pulls, &(&1.success == false)),
      total_mechanic_failures: total_failures,
      total_deaths: total_deaths,
      total_damage_taken: total_damage_taken,
      avg_failures_per_pull: average(total_failures, pull_count),
      avg_damage_taken: average(total_damage_taken, pull_count),
      current_failure_delta: performance_delta(current_pull, previous_pull, :mechanic_failures),
      current_death_delta: performance_delta(current_pull, previous_pull, :death_count),
      current_damage_taken_delta: performance_delta(current_pull, previous_pull, :damage_taken)
    }
  end

  defp previous_performance_pull(pulls, current_encounter_id) do
    pulls
    |> Enum.drop_while(&(&1.encounter_dim_id != current_encounter_id))
    |> Enum.drop(1)
    |> List.first()
  end

  defp performance_delta(nil, _previous, _field), do: nil
  defp performance_delta(_current, nil, _field), do: nil

  defp performance_delta(current, previous, field) do
    Map.fetch!(current, field) - Map.fetch!(previous, field)
  end

  defp average(_total, 0), do: 0.0
  defp average(total, count), do: Float.round(total / count, 1)

  defp personal_totals(encounter_dim_id, player_guid) do
    %{}
    |> Map.merge(damage_taken_totals(encounter_dim_id, player_guid))
    |> Map.merge(damage_done_totals(encounter_dim_id, player_guid))
    |> Map.merge(interrupt_totals(encounter_dim_id, player_guid))
    |> Map.merge(death_totals(encounter_dim_id, player_guid))
    |> Map.merge(failure_totals(encounter_dim_id, player_guid))
  end

  defp defensive_analysis(encounter_dim_id, player_guid) do
    windows = defensive_windows(encounter_dim_id, player_guid)

    events =
      encounter_dim_id
      |> dangerous_events(player_guid)
      |> Enum.map(&Map.put(&1, :active_defensives, active_defensives(windows, &1.occurred_at_ms)))
      |> Enum.map(&Map.put(&1, :covered, &1.active_defensives != []))

    %{
      windows: windows,
      events: events,
      summary: defensive_summary(windows, events)
    }
  end

  defp defensive_windows(encounter_dim_id, player_guid) do
    DefensiveBuffWindow
    |> where(
      [window],
      window.encounter_dim_id == ^encounter_dim_id and window.target_guid == ^player_guid
    )
    |> order_by([window], asc: window.started_at_ms_into_fight, asc: window.spell_name)
    |> select([window], %{
      spell_id: window.spell_id,
      spell_name: window.spell_name,
      category: window.category,
      source_guid: window.source_guid,
      started_at_ms: window.started_at_ms_into_fight,
      ended_at_ms: window.ended_at_ms_into_fight,
      duration_ms: window.duration_ms
    })
    |> Repo.all()
  end

  defp dangerous_events(encounter_dim_id, player_guid) do
    (failure_damage_events(encounter_dim_id, player_guid) ++
       death_danger_events(encounter_dim_id, player_guid))
    |> Enum.sort_by(&{&1.occurred_at_ms, &1.type, &1.spell_name || ""})
  end

  defp failure_damage_events(encounter_dim_id, player_guid) do
    DamageTakenEvent
    |> join(:inner, [event], player in DimPlayer, on: player.player_guid == event.target_guid)
    |> join(:inner, [event, player], failure in FactFailure,
      on:
        failure.encounter_dim_id == event.encounter_dim_id and
          failure.player_dim_id == player.id
    )
    |> join(:inner, [event, player, failure], criterion in DimMechanicCriterion,
      on: criterion.id == failure.criterion_dim_id and criterion.spell_id == event.spell_id
    )
    |> where(
      [event, player, failure, criterion],
      event.encounter_dim_id == ^encounter_dim_id and event.target_guid == ^player_guid
    )
    |> order_by([event, player, failure, criterion],
      asc: event.occurred_at_ms_into_fight,
      asc: event.combat_log_event_index
    )
    |> select([event, player, failure, criterion], %{
      type: :failure_damage,
      occurred_at_ms: event.occurred_at_ms_into_fight,
      spell_id: event.spell_id,
      spell_name: event.spell_name,
      mechanic_name: criterion.spell_name,
      amount: event.amount,
      overkill: event.overkill
    })
    |> Repo.all()
  end

  defp death_danger_events(encounter_dim_id, player_guid) do
    Death
    |> where(
      [death],
      death.encounter_dim_id == ^encounter_dim_id and death.target_guid == ^player_guid
    )
    |> order_by([death], asc: death.died_at_ms_into_fight)
    |> select([death], %{
      type: :death,
      occurred_at_ms: death.died_at_ms_into_fight,
      spell_id: death.killing_blow_spell_id,
      spell_name: nil,
      mechanic_name: nil,
      amount: 0,
      overkill: 0
    })
    |> Repo.all()
    |> Enum.map(fn event ->
      %{
        event
        | spell_name: death_spell_name(event.spell_id),
          mechanic_name: death_spell_name(event.spell_id)
      }
    end)
  end

  defp active_defensives(windows, occurred_at_ms) do
    Enum.filter(windows, fn window ->
      window.started_at_ms <= occurred_at_ms and
        (is_nil(window.ended_at_ms) or window.ended_at_ms >= occurred_at_ms)
    end)
  end

  defp defensive_summary(windows, events) do
    covered_count = Enum.count(events, & &1.covered)
    death_events = Enum.filter(events, &(&1.type == :death))

    %{
      windows_count: length(windows),
      dangerous_events_count: length(events),
      covered_events_count: covered_count,
      uncovered_events_count: length(events) - covered_count,
      death_events_count: length(death_events),
      covered_death_count: Enum.count(death_events, & &1.covered)
    }
  end

  defp death_spell_name(nil), do: "Death"
  defp death_spell_name(spell_id), do: Spells.name(spell_id)

  defp damage_taken_totals(encounter_dim_id, player_guid) do
    result =
      DamageTaken
      |> where(
        [row],
        row.encounter_dim_id == ^encounter_dim_id and row.target_guid == ^player_guid
      )
      |> select([row], %{
        damage_taken: coalesce(sum(row.total_amount), 0),
        damage_taken_hits: coalesce(sum(row.hit_count), 0),
        max_damage_taken_hit: coalesce(max(row.max_hit), 0),
        overkill_total: coalesce(sum(row.overkill_total), 0)
      })
      |> Repo.one()

    %{
      damage_taken: integer_value(result.damage_taken),
      damage_taken_hits: integer_value(result.damage_taken_hits),
      max_damage_taken_hit: integer_value(result.max_damage_taken_hit),
      overkill_total: integer_value(result.overkill_total)
    }
  end

  defp damage_done_totals(encounter_dim_id, player_guid) do
    result =
      DamageDone
      |> where(
        [row],
        row.encounter_dim_id == ^encounter_dim_id and row.source_guid == ^player_guid
      )
      |> select([row], %{
        damage_done: coalesce(sum(row.total_amount), 0),
        damage_done_hits: coalesce(sum(row.hit_count), 0),
        max_damage_done_hit: coalesce(max(row.max_hit), 0)
      })
      |> Repo.one()

    %{
      damage_done: integer_value(result.damage_done),
      damage_done_hits: integer_value(result.damage_done_hits),
      max_damage_done_hit: integer_value(result.max_damage_done_hit)
    }
  end

  defp interrupt_totals(encounter_dim_id, player_guid) do
    result =
      InterruptOpportunity
      |> where(
        [row],
        row.encounter_dim_id == ^encounter_dim_id and row.interrupter_guid == ^player_guid and
          row.success == true
      )
      |> select([row], %{
        successful_interrupts: count(row.id),
        interrupted_spell_count: count(row.interrupted_spell_id, :distinct)
      })
      |> Repo.one()

    %{
      successful_interrupts: integer_value(result.successful_interrupts),
      interrupted_spell_count: integer_value(result.interrupted_spell_count)
    }
  end

  defp death_totals(encounter_dim_id, player_guid) do
    result =
      Death
      |> where(
        [row],
        row.encounter_dim_id == ^encounter_dim_id and row.target_guid == ^player_guid
      )
      |> select([row], %{
        death_count: count(row.id),
        first_death_ms: min(row.died_at_ms_into_fight)
      })
      |> Repo.one()

    %{
      death_count: integer_value(result.death_count),
      first_death_ms: nullable_integer_value(result.first_death_ms)
    }
  end

  defp failure_totals(encounter_dim_id, player_guid) do
    result =
      FactFailure
      |> join(:inner, [failure], player in assoc(failure, :player))
      |> where(
        [failure, player],
        failure.encounter_dim_id == ^encounter_dim_id and player.player_guid == ^player_guid
      )
      |> select([failure, player], %{
        mechanic_failures: coalesce(sum(failure.failure_count), 0),
        failure_damage: coalesce(sum(failure.total_damage), 0),
        failed_mechanic_count: count(failure.criterion_dim_id, :distinct)
      })
      |> Repo.one()

    %{
      mechanic_failures: integer_value(result.mechanic_failures),
      failure_damage: integer_value(result.failure_damage),
      failed_mechanic_count: integer_value(result.failed_mechanic_count)
    }
  end

  defp integer_value(nil), do: 0
  defp integer_value(%Decimal{} = value), do: Decimal.to_integer(value)
  defp integer_value(value) when is_integer(value), do: value

  defp nullable_integer_value(nil), do: nil
  defp nullable_integer_value(value), do: integer_value(value)

  defp selected_personal_player_guid([], _preferred_character_name), do: nil

  defp selected_personal_player_guid(players, preferred_character_name)
       when is_binary(preferred_character_name) do
    normalized = normalize_name(preferred_character_name)

    case Enum.find(players, &(normalize_name(&1.player_name) == normalized)) do
      %{player_guid: player_guid} -> player_guid
      nil -> selected_personal_player_guid(players, nil)
    end
  end

  defp selected_personal_player_guid([player | _players], _preferred_character_name) do
    player.player_guid
  end

  defp normalize_name(name) when is_binary(name) do
    name
    |> String.split("-")
    |> List.first()
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_name(_name), do: ""

  defp parse_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed_id, ""} when parsed_id > 0 -> {:ok, parsed_id}
      _ -> :error
    end
  end

  defp parse_id(_id), do: :error
end
