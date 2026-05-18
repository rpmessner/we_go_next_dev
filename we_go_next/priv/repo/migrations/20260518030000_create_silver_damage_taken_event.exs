defmodule WeGoNext.Repo.Migrations.CreateSilverDamageTakenEvent do
  use Ecto.Migration

  def change do
    create table(:damage_taken_event, prefix: "silver") do
      add(:encounter_dim_id, references(:dim_encounter, prefix: "gold", on_delete: :delete_all),
        null: false
      )

      add(:combat_log_event_index, :integer, null: false)
      add(:event_type, :string, null: false)
      add(:occurred_at_ms_into_fight, :integer, null: false)
      add(:timestamp, :string)
      add(:target_guid, :string, null: false)
      add(:target_name, :string)
      add(:source_guid, :string, null: false)
      add(:source_name, :string)
      add(:source_is_npc, :boolean, null: false, default: false)
      add(:spell_id, :integer, null: false)
      add(:spell_name, :string)
      add(:spell_school, :integer)
      add(:amount, :bigint, null: false, default: 0)
      add(:overkill, :bigint, null: false, default: 0)

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:damage_taken_event, [:encounter_dim_id], prefix: "silver"))
    create(index(:damage_taken_event, [:encounter_dim_id, :target_guid], prefix: "silver"))
    create(index(:damage_taken_event, [:encounter_dim_id, :spell_id], prefix: "silver"))

    create(
      unique_index(:damage_taken_event, [:encounter_dim_id, :combat_log_event_index],
        prefix: "silver",
        name: :silver_damage_taken_event_natural_key
      )
    )
  end
end
