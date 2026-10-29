defmodule WeGoNext.Repo.Migrations.CreateAnalysisSessions do
  use Ecto.Migration

  def change do
    execute("CREATE SCHEMA analysis", "DROP SCHEMA analysis")

    create table(:sessions, prefix: "analysis", primary_key: false) do
      add :id, :uuid, primary_key: true
      add :started_at, :utc_datetime_usec, null: false
      add :combat_log_file_id, references(:combat_log_files, prefix: "public", on_delete: :restrict), null: false
      add :boss, :text
    end

    create table(:tool_calls, prefix: "analysis") do
      # Nullable only for rejected calls carrying an unknown/missing session id.
      add :session_id, references(:sessions, prefix: "analysis", type: :uuid, on_delete: :restrict)
      add :tool, :text, null: false
      add :args, :map, null: false
      add :result, :map, null: false
      add :result_size, :integer, null: false
      add :duration_ms, :integer, null: false
      add :truncated, :boolean, null: false, default: false
      add :error, :text
      add :called_at, :utc_datetime_usec, null: false
    end

    create index(:tool_calls, [:session_id, :id], prefix: "analysis")
    create index(:sessions, [:combat_log_file_id, :started_at], prefix: "analysis")
  end
end
