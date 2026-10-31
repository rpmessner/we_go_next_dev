defmodule WeGoNext.Repo.Migrations.AddFailureDerivationToDimEncounter do
  use Ecto.Migration

  def change do
    alter table(:dim_encounter, prefix: "gold") do
      # NULL: never proven rebuilt (including legacy zero-row pulls).
      # -1: coordinated rebuild incomplete; positive: completed derivation.
      add :failure_derivation_version, :integer
    end
  end
end
