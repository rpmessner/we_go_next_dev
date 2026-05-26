defmodule WeGoNext.Repo.Migrations.ReworkSilverEncounterDimensionKey do
  use Ecto.Migration

  def up do
    drop_if_exists(table(:player_info, prefix: "silver"))
    drop_if_exists(table(:debuff_application, prefix: "silver"))
    drop_if_exists(table(:interrupt_opportunity, prefix: "silver"))
    drop_if_exists(table(:death, prefix: "silver"))
    drop_if_exists(table(:damage_done, prefix: "silver"))
    drop_if_exists(table(:damage_taken, prefix: "silver"))

    create table(:damage_taken, prefix: "silver") do
      add(:encounter_dim_id, references(:dim_encounter, prefix: "gold", on_delete: :delete_all),
        null: false
      )

      add(:target_guid, :string, null: false)
      add(:source_guid, :string, null: false)
      add(:spell_id, :integer, null: false)
      add(:total_amount, :bigint, null: false, default: 0)
      add(:hit_count, :integer, null: false, default: 0)
      add(:max_hit, :bigint, null: false, default: 0)
      add(:overkill_total, :bigint, null: false, default: 0)
      add(:source_is_npc, :boolean, null: false, default: false)

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:damage_taken, [:encounter_dim_id], prefix: "silver"))

    create(
      unique_index(:damage_taken, [:encounter_dim_id, :target_guid, :source_guid, :spell_id],
        prefix: "silver",
        name: :silver_damage_taken_natural_key
      )
    )

    create table(:damage_done, prefix: "silver") do
      add(:encounter_dim_id, references(:dim_encounter, prefix: "gold", on_delete: :delete_all),
        null: false
      )

      add(:source_guid, :string, null: false)
      add(:target_guid, :string, null: false)
      add(:spell_id, :integer, null: false)
      add(:total_amount, :bigint, null: false, default: 0)
      add(:hit_count, :integer, null: false, default: 0)
      add(:max_hit, :bigint, null: false, default: 0)

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:damage_done, [:encounter_dim_id], prefix: "silver"))

    create(
      unique_index(:damage_done, [:encounter_dim_id, :source_guid, :target_guid, :spell_id],
        prefix: "silver",
        name: :silver_damage_done_natural_key
      )
    )

    create table(:death, prefix: "silver") do
      add(:encounter_dim_id, references(:dim_encounter, prefix: "gold", on_delete: :delete_all),
        null: false
      )

      add(:target_guid, :string, null: false)
      add(:died_at_ms_into_fight, :integer, null: false)
      add(:killing_blow_spell_id, :integer)
      add(:killing_blow_source_guid, :string)
      add(:damage_recap, {:array, :map}, null: false, default: [])

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:death, [:encounter_dim_id], prefix: "silver"))

    create(
      unique_index(:death, [:encounter_dim_id, :target_guid, :died_at_ms_into_fight],
        prefix: "silver",
        name: :silver_death_natural_key
      )
    )

    create table(:interrupt_opportunity, prefix: "silver") do
      add(:encounter_dim_id, references(:dim_encounter, prefix: "gold", on_delete: :delete_all),
        null: false
      )

      add(:target_npc_guid, :string, null: false)
      add(:interrupted_spell_id, :integer, null: false)
      add(:opportunity_ms_into_fight, :integer, null: false)
      add(:success, :boolean, null: false)
      add(:interrupter_guid, :string)
      add(:interrupting_spell_id, :integer)

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:interrupt_opportunity, [:encounter_dim_id], prefix: "silver"))

    create(
      unique_index(
        :interrupt_opportunity,
        [:encounter_dim_id, :target_npc_guid, :interrupted_spell_id, :opportunity_ms_into_fight],
        prefix: "silver",
        name: :silver_interrupt_opportunity_natural_key
      )
    )

    create table(:debuff_application, prefix: "silver") do
      add(:encounter_dim_id, references(:dim_encounter, prefix: "gold", on_delete: :delete_all),
        null: false
      )

      add(:target_guid, :string, null: false)
      add(:source_guid, :string, null: false)
      add(:spell_id, :integer, null: false)
      add(:applied_at_ms_into_fight, :integer, null: false)
      add(:duration_ms, :integer)
      add(:stack_count, :integer, null: false, default: 1)

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:debuff_application, [:encounter_dim_id], prefix: "silver"))

    create(
      unique_index(
        :debuff_application,
        [:encounter_dim_id, :target_guid, :source_guid, :spell_id, :applied_at_ms_into_fight],
        prefix: "silver",
        name: :silver_debuff_application_natural_key
      )
    )

    create table(:player_info, prefix: "silver") do
      add(:encounter_dim_id, references(:dim_encounter, prefix: "gold", on_delete: :delete_all),
        null: false
      )

      add(:player_guid, :string, null: false)
      add(:player_name, :string, null: false)
      add(:class_id, :integer)
      add(:spec_id, :integer)
      add(:item_level, :integer)
      add(:detected_role, :string, null: false, default: "unknown")

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:player_info, [:encounter_dim_id], prefix: "silver"))

    create(
      unique_index(:player_info, [:encounter_dim_id, :player_guid],
        prefix: "silver",
        name: :silver_player_info_natural_key
      )
    )

    create(
      constraint(:player_info, :silver_player_info_detected_role_check,
        prefix: "silver",
        check: "detected_role IN ('tank', 'healer', 'dps', 'unknown')"
      )
    )
  end

  def down do
    raise "irreversible silver encounter dimension rekey"
  end
end
