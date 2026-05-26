defmodule WeGoNext.Repo.Migrations.CreateSilverDefensiveBuffWindow do
  use Ecto.Migration

  def change do
    create table(:defensive_buff_window, prefix: "silver") do
      add(:encounter_dim_id, references(:dim_encounter, prefix: "gold", on_delete: :delete_all),
        null: false
      )

      add(:target_guid, :string, null: false)
      add(:source_guid, :string, null: false)
      add(:spell_id, :integer, null: false)
      add(:spell_name, :string, null: false)
      add(:category, :string, null: false)
      add(:started_at_ms_into_fight, :integer, null: false)
      add(:ended_at_ms_into_fight, :integer)
      add(:duration_ms, :integer)

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(index(:defensive_buff_window, [:encounter_dim_id], prefix: "silver"))
    create(index(:defensive_buff_window, [:encounter_dim_id, :target_guid], prefix: "silver"))

    create(
      unique_index(
        :defensive_buff_window,
        [:encounter_dim_id, :target_guid, :source_guid, :spell_id, :started_at_ms_into_fight],
        prefix: "silver",
        name: :silver_defensive_buff_window_natural_key
      )
    )
  end
end
