defmodule WeGoNext.Repo.Migrations.PersistImportOperations do
  use Ecto.Migration

  def change do
    create table(:import_operations) do
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:token, :uuid, null: false)
      add(:path, :text, null: false)
      add(:status, :string, null: false)
      add(:started_at, :utc_datetime_usec, null: false)
      add(:deadline, :utc_datetime_usec, null: false)
      add(:error, :text)
      add(:encounters, :integer)
    end

    create(unique_index(:import_operations, [:user_id]))

    create(
      constraint(:import_operations, :import_operations_status_check,
        check: "status IN ('importing', 'complete', 'failed')"
      )
    )
  end
end
