defmodule WeGoNext.Repo.Migrations.TrackIngestMedallionWork do
  use Ecto.Migration

  def change do
    alter table(:encounters) do
      add(:medallion_state, :string, null: false, default: "pending")
      add(:medallion_error, :text)
    end

    create(
      constraint(:encounters, :encounters_medallion_state_check,
        check: "medallion_state IN ('pending', 'failed', 'complete')"
      )
    )
  end
end
