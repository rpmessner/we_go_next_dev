defmodule WeGoNext.Repo.Migrations.CreateAnalysisVerdicts do
  use Ecto.Migration

  def change do
    create table(:verdicts, prefix: "analysis") do
      add(
        :session_id,
        references(:sessions, prefix: "analysis", type: :uuid, on_delete: :restrict), null: false)

      add(:answer, :text, null: false)
      add(:verdict, :text, null: false)
      add(:correction, :text, null: false)
      add(:recorded_at, :utc_datetime_usec, null: false)
    end

    create(
      constraint(:verdicts, :valid_verdict,
        prefix: "analysis",
        check: "verdict IN ('correct', 'partly', 'wrong')"
      )
    )

    create(index(:verdicts, [:session_id, :id], prefix: "analysis"))
  end
end
