defmodule WeGoNext.Repo.Migrations.AddPublicMirrorKeys do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS pgcrypto", "")

    alter table(:dim_encounter, prefix: "gold") do
      add(:source_encounter_key, :string)
    end

    alter table(:dim_mechanic_criterion, prefix: "gold") do
      add(:criterion_key, :string)
    end

    execute(
      """
      UPDATE gold.dim_encounter
      SET source_encounter_key = encode(
        digest(
          concat_ws(
            chr(31),
            source_head_sha256,
            start_byte::text,
            end_byte::text,
            wow_encounter_id,
            start_time::text
          ),
          'sha256'
        ),
        'hex'
      )
      WHERE source_encounter_key IS NULL
        AND source_head_sha256 IS NOT NULL
        AND start_byte IS NOT NULL
        AND end_byte IS NOT NULL
        AND wow_encounter_id IS NOT NULL
        AND start_time IS NOT NULL
      """,
      "UPDATE gold.dim_encounter SET source_encounter_key = NULL"
    )

    execute(
      """
      UPDATE gold.dim_mechanic_criterion
      SET criterion_key = encode(
        digest(
          concat_ws(
            chr(31),
            COALESCE(product, ''),
            COALESCE(channel, ''),
            COALESCE(build_key, ''),
            COALESCE(boss_encounter_id, ''),
            COALESCE(difficulty_id::text, ''),
            spell_id::text,
            mechanic_type,
            encode(
              digest(
                concat_ws(
                  chr(31),
                  regexp_replace(
                    regexp_replace(
                      COALESCE(threshold::jsonb::text, '{}'::jsonb::text),
                      ': ',
                      ':',
                      'g'
                    ),
                    ', ',
                    ',',
                    'g'
                  ),
                  CASE mechanic_type
                    WHEN 'avoidable' THEN '1'
                    WHEN 'interrupt' THEN '1'
                    WHEN 'targeted_cone' THEN '1'
                    WHEN 'soak' THEN '1'
                    WHEN 'spread' THEN '1'
                    WHEN 'stack' THEN '1'
                    WHEN 'tank_mechanic' THEN '1'
                    WHEN 'healer_mechanic' THEN '1'
                    ELSE '1'
                  END
                ),
                'sha256'
              ),
              'hex'
            )
          ),
          'sha256'
        ),
        'hex'
      )
      WHERE criterion_key IS NULL
      """,
      "UPDATE gold.dim_mechanic_criterion SET criterion_key = NULL"
    )

    alter table(:dim_mechanic_criterion, prefix: "gold") do
      modify(:criterion_key, :string, null: false)
    end

    create(unique_index(:dim_encounter, [:source_encounter_key], prefix: "gold"))
    create(unique_index(:dim_mechanic_criterion, [:criterion_key], prefix: "gold"))
  end
end
