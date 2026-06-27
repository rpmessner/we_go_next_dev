defmodule WeGoNext.Repo.Migrations.CreateSourceDataWarcraftLogsApiFetch do
  use Ecto.Migration

  def change do
    create table(:warcraft_logs_api_fetch, prefix: "source_data") do
      add(
        :source_import_id,
        references(:source_import, prefix: "source_data", on_delete: :delete_all),
        null: false
      )

      add(:report_code, :string, null: false)
      add(:fight_id, :integer, null: false)
      add(:source_url, :text, null: false)
      add(:api_endpoint, :text)
      add(:api_version, :string, null: false, default: "v2")

      add(:query_name, :string, null: false)
      add(:query_document, :text)
      add(:query_hash, :string, null: false)
      add(:query_variables, :map, null: false, default: %{})
      add(:request_params, :map, null: false, default: %{})
      add(:request_hash, :string, null: false)

      add(:fetched_at, :utc_datetime_usec, null: false)
      add(:response_hash, :string, null: false)
      add(:response_payload, :map, null: false, default: %{})
      add(:metadata, :map, null: false, default: %{})

      add(:product, :string, null: false, default: "wow")
      add(:channel, :string, null: false, default: "retail")
      add(:build_version, :string)
      add(:build_key, :string)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:warcraft_logs_api_fetch, [:source_import_id], prefix: "source_data"))
    create(index(:warcraft_logs_api_fetch, [:report_code], prefix: "source_data"))
    create(index(:warcraft_logs_api_fetch, [:report_code, :fight_id], prefix: "source_data"))
    create(index(:warcraft_logs_api_fetch, [:request_hash], prefix: "source_data"))
    create(index(:warcraft_logs_api_fetch, [:response_hash], prefix: "source_data"))
    create(index(:warcraft_logs_api_fetch, [:fetched_at], prefix: "source_data"))
  end
end
