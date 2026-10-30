defmodule WeGoNext.Repo.Migrations.CreateAnalysisQuestionsAndMessages do
  use Ecto.Migration

  def change do
    alter table(:sessions, prefix: "analysis") do
      add(:model, :text, null: false, default: "claude-opus-5-5")
    end

    create table(:questions, primary_key: false, prefix: "analysis") do
      add(:id, :uuid, primary_key: true)

      add(
        :session_id,
        references(:sessions, type: :uuid, prefix: "analysis", on_delete: :restrict),
        null: false
      )

      add(:scope, :map, null: false, default: %{})
      add(:text, :text, null: false)
      add(:model, :text, null: false)
      add(:state, :text, null: false, default: "draft")
      add(:lifecycle, :map, null: false, default: %{})
      add(:answer, :text)
      add(:error, :text)
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:questions, [:session_id], prefix: "analysis"))

    create table(:messages, prefix: "analysis") do
      add(
        :session_id,
        references(:sessions, type: :uuid, prefix: "analysis", on_delete: :restrict),
        null: false
      )

      add(
        :question_id,
        references(:questions, type: :uuid, prefix: "analysis", on_delete: :restrict),
        null: false
      )

      add(:role, :text, null: false)
      add(:content, {:array, :map}, null: false)
      add(:usage, :map, null: false, default: %{})
      add(:stop_reason, :text)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:messages, [:session_id, :id], prefix: "analysis"))
    create(index(:messages, [:question_id, :id], prefix: "analysis"))
  end
end
