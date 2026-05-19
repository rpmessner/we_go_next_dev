defmodule WeGoNext.Gold.FactFailure.Query do
  @moduledoc """
  SQL assembly helpers for `gold.fact_failure` rebuilds.

  Mechanic builders emit CTEs with a shared row shape:
  `encounter_dim_id`, `player_dim_id`, `criterion_dim_id`,
  `failure_count`, and `total_damage`. Build and ruleset metadata are copied
  from the selected criterion snapshot at insert time.
  """

  @doc """
  CTE that binds the rebuild to one gold encounter dimension.
  """
  def encounter_scope_cte do
    """
    encounter_scope AS (
      SELECT id AS encounter_dim_id, wow_encounter_id, difficulty_id
      FROM gold.dim_encounter
      WHERE id = $1
    )
    """
  end

  @doc """
  Builds the insert statement from shared CTEs and registered mechanic builders.
  """
  def insert_sql(opts) do
    builders = Keyword.fetch!(opts, :builders)
    base_ctes = Keyword.fetch!(opts, :base_ctes)
    builder_opts = Keyword.get(opts, :builder_opts, [])

    builder_ctes = Enum.map(builders, & &1.cte(builder_opts))

    """
    WITH #{Enum.join(base_ctes ++ builder_ctes, ",\n")},
    fact_rows AS (
    #{fact_row_union(builders)}
    )
    INSERT INTO gold.fact_failure (
      encounter_dim_id,
      player_dim_id,
      criterion_dim_id,
      ruleset_id,
      ruleset_version,
      product,
      channel,
      build_version,
      build_key,
      failure_count,
      total_damage
    )
    SELECT
      rows.encounter_dim_id,
      rows.player_dim_id,
      rows.criterion_dim_id,
      criterion.ruleset_id,
      criterion.ruleset_version,
      criterion.product,
      criterion.channel,
      criterion.build_version,
      criterion.build_key,
      sum(failure_count)::integer AS failure_count,
      sum(total_damage)::bigint AS total_damage
    FROM fact_rows rows
    JOIN gold.dim_mechanic_criterion criterion
      ON criterion.id = rows.criterion_dim_id
    GROUP BY
      rows.encounter_dim_id,
      rows.player_dim_id,
      rows.criterion_dim_id,
      criterion.ruleset_id,
      criterion.ruleset_version,
      criterion.product,
      criterion.channel,
      criterion.build_version,
      criterion.build_key
    """
  end

  defp fact_row_union(builders) do
    builders
    |> Enum.map_join("\nUNION ALL\n", fn builder ->
      "      SELECT * FROM #{builder.cte_name()}"
    end)
  end
end
