defmodule WeGoNext.Repo.Migrations.CreateSilverTables do
  use Ecto.Migration

  def change do
    # All silver tables intentionally keep Ecto's default surrogate id.
    # Persistence can use replace_all_except: [:id, :inserted_at] on conflict.
    #
    # Natural-key columns are non-null. Projectors must normalize missing key values
    # before insert: spell_id 0 means melee/unknown spell, and __UNKNOWN_*__ string
    # sentinels mean a missing GUID in raw combat-log data.
    create table(:silver_damage_taken) do
      add(:encounter_id, references(:encounters, on_delete: :delete_all), null: false)
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

    create(index(:silver_damage_taken, [:encounter_id]))

    create(
      unique_index(:silver_damage_taken, [:encounter_id, :target_guid, :source_guid, :spell_id],
        name: :silver_damage_taken_natural_key
      )
    )

    create table(:silver_damage_done) do
      add(:encounter_id, references(:encounters, on_delete: :delete_all), null: false)
      add(:source_guid, :string, null: false)
      add(:target_guid, :string, null: false)
      add(:spell_id, :integer, null: false)
      add(:total_amount, :bigint, null: false, default: 0)
      add(:hit_count, :integer, null: false, default: 0)
      add(:max_hit, :bigint, null: false, default: 0)

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:silver_damage_done, [:encounter_id]))

    create(
      unique_index(:silver_damage_done, [:encounter_id, :source_guid, :target_guid, :spell_id],
        name: :silver_damage_done_natural_key
      )
    )

    create table(:silver_death) do
      add(:encounter_id, references(:encounters, on_delete: :delete_all), null: false)
      add(:target_guid, :string, null: false)
      add(:died_at_ms_into_fight, :integer, null: false)
      add(:killing_blow_spell_id, :integer)
      add(:killing_blow_source_guid, :string)
      add(:damage_recap, :map, null: false, default: fragment("'[]'::jsonb"))

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:silver_death, [:encounter_id]))

    create(
      unique_index(:silver_death, [:encounter_id, :target_guid, :died_at_ms_into_fight],
        name: :silver_death_natural_key
      )
    )

    create table(:silver_interrupt_opportunity) do
      add(:encounter_id, references(:encounters, on_delete: :delete_all), null: false)
      add(:target_npc_guid, :string, null: false)
      add(:interrupted_spell_id, :integer, null: false)
      add(:opportunity_ms_into_fight, :integer, null: false)
      add(:success, :boolean, null: false)
      add(:interrupter_guid, :string)
      add(:interrupting_spell_id, :integer)

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:silver_interrupt_opportunity, [:encounter_id]))

    create(
      unique_index(
        :silver_interrupt_opportunity,
        [:encounter_id, :target_npc_guid, :interrupted_spell_id, :opportunity_ms_into_fight],
        name: :silver_interrupt_opportunity_natural_key
      )
    )

    create table(:silver_debuff_application) do
      add(:encounter_id, references(:encounters, on_delete: :delete_all), null: false)
      add(:target_guid, :string, null: false)
      add(:source_guid, :string, null: false)
      add(:spell_id, :integer, null: false)
      add(:applied_at_ms_into_fight, :integer, null: false)
      add(:duration_ms, :integer)
      add(:stack_count, :integer, null: false, default: 1)

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:silver_debuff_application, [:encounter_id]))

    create(
      unique_index(
        :silver_debuff_application,
        [:encounter_id, :target_guid, :source_guid, :spell_id, :applied_at_ms_into_fight],
        name: :silver_debuff_application_natural_key
      )
    )

    create table(:silver_player_info) do
      add(:encounter_id, references(:encounters, on_delete: :delete_all), null: false)
      add(:player_guid, :string, null: false)
      add(:player_name, :string, null: false)
      add(:class_id, :integer)
      add(:spec_id, :integer)
      add(:item_level, :integer)
      add(:detected_role, :string, null: false, default: "unknown")

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:silver_player_info, [:encounter_id]))

    create(
      unique_index(:silver_player_info, [:encounter_id, :player_guid],
        name: :silver_player_info_natural_key
      )
    )

    create(
      constraint(:silver_player_info, :silver_player_info_detected_role_check,
        check: "detected_role IN ('tank', 'healer', 'dps', 'unknown')"
      )
    )
  end
end
