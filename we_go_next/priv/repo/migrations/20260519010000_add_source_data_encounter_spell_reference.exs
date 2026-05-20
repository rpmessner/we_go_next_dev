defmodule WeGoNext.Repo.Migrations.AddSourceDataEncounterSpellReference do
  use Ecto.Migration

  def up do
    drop(
      index(
        :encounter_reference,
        [:encounter_id, :product, :channel, :build_key, :locale, :source_system],
        prefix: "source_data",
        name: :encounter_reference_identity_index
      )
    )

    alter table(:encounter_reference, prefix: "source_data") do
      add(:difficulty_id, :integer, null: false, default: 0)
    end

    create(
      unique_index(
        :encounter_reference,
        [:encounter_id, :difficulty_id, :product, :channel, :build_key, :locale, :source_system],
        prefix: "source_data",
        name: :encounter_reference_identity_index
      )
    )

    create(
      index(
        :encounter_reference,
        [:encounter_id, :difficulty_id, :product, :channel, :build_key, :locale],
        prefix: "source_data",
        name: :encounter_reference_difficulty_lookup_index
      )
    )

    create table(:encounter_spell_reference, prefix: "source_data") do
      add(
        :source_import_id,
        references(:source_import, prefix: "source_data", on_delete: :nilify_all)
      )

      add(:encounter_id, :integer, null: false)
      add(:spell_id, :integer, null: false)
      add(:difficulty_id, :integer, null: false, default: 0)
      add(:relationship_type, :string, null: false, default: "mechanic")

      add(:product, :string, null: false)
      add(:channel, :string, null: false)
      add(:build_version, :string)
      add(:build_key, :string, null: false)
      add(:locale, :string, null: false, default: "enUS")

      add(:source_system, :string, null: false)
      add(:source_priority, :integer, null: false, default: 100)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:encounter_spell_reference, [:source_import_id], prefix: "source_data"))
    create(index(:encounter_spell_reference, [:spell_id], prefix: "source_data"))

    create(
      index(:encounter_spell_reference, [:encounter_id, :difficulty_id],
        prefix: "source_data",
        name: :encounter_spell_reference_encounter_scope_index
      )
    )

    create(
      unique_index(
        :encounter_spell_reference,
        [
          :encounter_id,
          :spell_id,
          :difficulty_id,
          :relationship_type,
          :product,
          :channel,
          :build_key,
          :locale,
          :source_system
        ],
        prefix: "source_data",
        name: :encounter_spell_reference_identity_index
      )
    )
  end

  def down do
    drop(table(:encounter_spell_reference, prefix: "source_data"))

    drop(
      index(
        :encounter_reference,
        [:encounter_id, :difficulty_id, :product, :channel, :build_key, :locale],
        prefix: "source_data",
        name: :encounter_reference_difficulty_lookup_index
      )
    )

    drop(
      index(
        :encounter_reference,
        [:encounter_id, :difficulty_id, :product, :channel, :build_key, :locale, :source_system],
        prefix: "source_data",
        name: :encounter_reference_identity_index
      )
    )

    alter table(:encounter_reference, prefix: "source_data") do
      remove(:difficulty_id)
    end

    create(
      unique_index(
        :encounter_reference,
        [:encounter_id, :product, :channel, :build_key, :locale, :source_system],
        prefix: "source_data",
        name: :encounter_reference_identity_index
      )
    )
  end
end
