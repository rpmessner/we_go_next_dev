defmodule WeGoNext.Repo.Migrations.CreateSourceDataReferenceDimensions do
  use Ecto.Migration

  def change do
    alter table(:source_import, prefix: "source_data") do
      add(:channel, :string, null: false, default: "retail")
    end

    create table(:spell_reference, prefix: "source_data") do
      add(
        :source_import_id,
        references(:source_import, prefix: "source_data", on_delete: :nilify_all)
      )

      add(:spell_id, :integer, null: false)
      add(:current_name, :string, null: false)
      add(:localized_names, :map, null: false, default: %{})

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

    create(index(:spell_reference, [:source_import_id], prefix: "source_data"))

    create(
      index(:spell_reference, [:spell_id, :product, :channel, :build_key, :locale],
        prefix: "source_data",
        name: :spell_reference_lookup_index
      )
    )

    create(
      unique_index(
        :spell_reference,
        [:spell_id, :product, :channel, :build_key, :locale, :source_system],
        prefix: "source_data",
        name: :spell_reference_identity_index
      )
    )

    create table(:encounter_reference, prefix: "source_data") do
      add(
        :source_import_id,
        references(:source_import, prefix: "source_data", on_delete: :nilify_all)
      )

      add(:encounter_id, :integer, null: false)
      add(:current_name, :string, null: false)
      add(:localized_names, :map, null: false, default: %{})
      add(:zone_id, :integer)
      add(:zone_name, :string)
      add(:instance_id, :integer)
      add(:instance_name, :string)

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

    create(index(:encounter_reference, [:source_import_id], prefix: "source_data"))

    create(
      index(:encounter_reference, [:encounter_id, :product, :channel, :build_key, :locale],
        prefix: "source_data",
        name: :encounter_reference_lookup_index
      )
    )

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
