defmodule WeGoNext.Gold.FactFailure.Builders.MissedInterrupt do
  @moduledoc """
  Emits failure rows for missed interrupt criteria.

  Semantics: each unsuccessful interrupt opportunity for a matching spell is
  attributed to the raid sentinel rather than an individual player.
  """

  def cte_name, do: "interrupt_rows"

  def cte(opts \\ []) do
    raid_player_guid = Keyword.fetch!(opts, :raid_player_guid)

    """
    #{cte_name()} AS (
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
        ON raid.player_guid = '#{raid_player_guid}'
      WHERE io.success = FALSE
      GROUP BY e.encounter_dim_id, raid.id, sc.id
    )
    """
  end
end
