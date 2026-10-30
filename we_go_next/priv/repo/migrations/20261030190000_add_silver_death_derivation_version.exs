defmodule WeGoNext.Repo.Migrations.AddSilverDeathDerivationVersion do
  use Ecto.Migration

  def change do
    alter table(:dim_encounter, prefix: "gold") do
      # NULL deliberately means pre-stamp/unknown, not current.
      add :silver_death_derivation_version, :integer
    end
  end
end
