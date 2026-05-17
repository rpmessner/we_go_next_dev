defmodule WeGoNext.Gold.FactFailure do
  @moduledoc """
  Gold fact row for mechanic failures by encounter, player, and criterion.
  """

  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset

  alias WeGoNext.Gold.{DimEncounter, DimMechanicCriterion, DimPlayer}
  alias WeGoNext.Repo

  @primary_key false
  @schema_prefix "gold"
  @raid_player_guid "__RAID__"

  schema "fact_failure" do
    field(:failure_count, :integer)
    field(:total_damage, :integer, default: 0)

    belongs_to(:encounter, DimEncounter, foreign_key: :encounter_dim_id, primary_key: true)
    belongs_to(:player, DimPlayer, foreign_key: :player_dim_id, primary_key: true)

    belongs_to(:criterion, DimMechanicCriterion,
      foreign_key: :criterion_dim_id,
      primary_key: true
    )
  end

  @doc false
  def changeset(fact_failure, attrs) do
    fact_failure
    |> cast(attrs, [
      :encounter_dim_id,
      :player_dim_id,
      :criterion_dim_id,
      :failure_count,
      :total_damage
    ])
    |> validate_required([
      :encounter_dim_id,
      :player_dim_id,
      :criterion_dim_id,
      :failure_count,
      :total_damage
    ])
  end

  @doc """
  Rebuilds mechanic failure facts for one gold encounter dimension.
  """
  @spec rebuild_for_encounter(pos_integer()) ::
          {:ok, %{deleted: non_neg_integer(), inserted: non_neg_integer()}} | {:error, term()}
  def rebuild_for_encounter(encounter_dim_id) when is_integer(encounter_dim_id) do
    Repo.transaction(fn ->
      ensure_raid_sentinel!()

      dim_encounter =
        case Repo.get(DimEncounter, encounter_dim_id) do
          %DimEncounter{} = dim_encounter -> dim_encounter
          nil -> Repo.rollback(:encounter_not_found)
        end

      DimPlayer.upsert_from_silver(dim_encounter.id)

      {deleted, _} =
        from(failure in __MODULE__, where: failure.encounter_dim_id == ^dim_encounter.id)
        |> Repo.delete_all()

      case Repo.query(rebuild_sql(), [dim_encounter.id]) do
        {:ok, %{num_rows: inserted}} -> %{deleted: deleted, inserted: inserted}
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp ensure_raid_sentinel! do
    Repo.insert_all(
      DimPlayer,
      [
        %{
          player_guid: @raid_player_guid,
          player_name: "Raid"
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:player_guid]
    )
  end

  defp rebuild_sql do
    """
    WITH encounter_scope AS (
      SELECT id AS encounter_dim_id, wow_encounter_id, difficulty_id
      FROM gold.dim_encounter
      WHERE id = $1
    ),
    selected_criteria AS (
      SELECT *
      FROM (
        SELECT
          c.*,
          row_number() OVER (
            PARTITION BY c.spell_id
            ORDER BY
              CASE
                WHEN c.boss_encounter_id IS NULL THEN 0
                WHEN c.difficulty_id IS NULL THEN 1
                WHEN c.difficulty_id = 14 THEN 2
                WHEN c.difficulty_id = 15 THEN 3
                WHEN c.difficulty_id = 16 THEN 4
                ELSE 1
              END DESC,
              c.id ASC
          ) AS specificity_rank
        FROM gold.dim_mechanic_criterion c
        JOIN encounter_scope e ON TRUE
        WHERE c.active = TRUE
          AND (
            c.boss_encounter_id IS NULL
            OR (
              c.boss_encounter_id = e.wow_encounter_id
              AND (
                c.difficulty_id IS NULL
                OR c.difficulty_id = ANY(
                  CASE
                    WHEN e.difficulty_id = 14 THEN ARRAY[14]
                    WHEN e.difficulty_id = 15 THEN ARRAY[14, 15]
                    WHEN e.difficulty_id = 16 THEN ARRAY[14, 15, 16]
                    ELSE ARRAY[14, 15, 16]
                  END
                )
              )
            )
          )
      ) ranked_criteria
      WHERE specificity_rank = 1
    ),
    avoidable_rows AS (
      SELECT
        e.encounter_dim_id,
        dp.id AS player_dim_id,
        sc.id AS criterion_dim_id,
        sum(dt.hit_count)::integer AS failure_count,
        sum(dt.total_amount)::bigint AS total_damage
      FROM silver.damage_taken dt
      JOIN encounter_scope e
        ON e.encounter_dim_id = dt.encounter_dim_id
      JOIN silver.player_info pi
        ON pi.encounter_dim_id = dt.encounter_dim_id
       AND pi.player_guid = dt.target_guid
      JOIN gold.dim_player dp
        ON dp.player_guid = pi.player_guid
      JOIN selected_criteria sc
        ON sc.spell_id = dt.spell_id
       AND sc.mechanic_type = 'avoidable'
      GROUP BY e.encounter_dim_id, dp.id, sc.id, sc.threshold
      HAVING sum(dt.hit_count) > CASE
        WHEN COALESCE(sc.threshold->>'max_hits', '') ~ '^[0-9]+$'
          THEN (sc.threshold->>'max_hits')::integer
        ELSE 0
      END
    ),
    interrupt_rows AS (
      SELECT
        e.encounter_dim_id,
        raid.id AS player_dim_id,
        sc.id AS criterion_dim_id,
        count(*)::integer AS failure_count,
        0::bigint AS total_damage
      FROM silver.interrupt_opportunity io
      JOIN encounter_scope e
        ON e.encounter_dim_id = io.encounter_dim_id
      JOIN selected_criteria sc
        ON sc.spell_id = io.interrupted_spell_id
       AND sc.mechanic_type = 'interrupt'
      JOIN gold.dim_player raid
        ON raid.player_guid = '#{@raid_player_guid}'
      WHERE io.success = FALSE
      GROUP BY e.encounter_dim_id, raid.id, sc.id
    ),
    fact_rows AS (
      SELECT * FROM avoidable_rows
      UNION ALL
      SELECT * FROM interrupt_rows
    )
    INSERT INTO gold.fact_failure (
      encounter_dim_id,
      player_dim_id,
      criterion_dim_id,
      failure_count,
      total_damage
    )
    SELECT
      encounter_dim_id,
      player_dim_id,
      criterion_dim_id,
      sum(failure_count)::integer AS failure_count,
      sum(total_damage)::bigint AS total_damage
    FROM fact_rows
    GROUP BY encounter_dim_id, player_dim_id, criterion_dim_id
    """
  end
end
