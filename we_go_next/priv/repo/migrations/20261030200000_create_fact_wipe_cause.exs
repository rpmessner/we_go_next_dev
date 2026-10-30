defmodule WeGoNext.Repo.Migrations.CreateFactWipeCause do
  use Ecto.Migration

  def change do
    create table(:fact_wipe_cause, prefix: "gold", primary_key: false) do
      add :encounter_dim_id, references(:dim_encounter, prefix: "gold", on_delete: :delete_all), primary_key: true
      add :rank, :integer, primary_key: true
      add :player_guid, :text, null: false
      add :player_name, :text
      add :died_at_ms_into_fight, :bigint, null: false
      add :killing_blow_spell_id, :bigint
      add :killing_blow_spell_name, :text
      add :killing_blow_source_guid, :text
      add :killing_blow_source_name, :text
      add :mechanic_name, :text
      add :mechanic_type, :text
      add :avoidable, :boolean
      add :derivation_version, :integer, null: false
      add :rebuilt_at, :utc_datetime_usec, null: false
    end

    create constraint(:fact_wipe_cause, :wipe_cause_rank, prefix: "gold", check: "rank BETWEEN 1 AND 3")

    alter table(:dim_encounter, prefix: "gold") do
      add :wipe_cause_derivation_version, :integer
    end
  end
end
