defmodule WeGoNext.Repo.Migrations.CreateSilverSurvivalAction do
  use Ecto.Migration

  def change do
    create table(:survival_action, prefix: "silver") do
      add(:encounter_dim_id, references(:dim_encounter, prefix: "gold", on_delete: :delete_all),
        null: false
      )

      add(:caster_guid, :string, null: false)
      add(:target_guid, :string, null: false)
      add(:spell_id, :integer, null: false)
      add(:spell_name, :string, null: false)
      add(:kind, :string, null: false)
      add(:category, :string, null: false)
      add(:used_at_ms_into_fight, :integer, null: false)
      add(:heal_amount, :bigint)
      add(:overheal_amount, :bigint)

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:survival_action, [:encounter_dim_id], prefix: "silver"))
    create(index(:survival_action, [:encounter_dim_id, :target_guid], prefix: "silver"))

    create(
      unique_index(
        :survival_action,
        [:encounter_dim_id, :caster_guid, :target_guid, :spell_id, :used_at_ms_into_fight],
        prefix: "silver",
        name: :silver_survival_action_natural_key
      )
    )
  end
end
