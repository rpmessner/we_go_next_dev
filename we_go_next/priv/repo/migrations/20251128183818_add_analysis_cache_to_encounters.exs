defmodule WeGoNext.Repo.Migrations.AddAnalysisCacheToEncounters do
  use Ecto.Migration

  def change do
    alter table(:encounters) do
      # Pre-computed analysis results (deaths, damage taken, failures, etc.)
      add :analysis, :map, default: %{}
      # Storage tier: "hot" (full raw_log), "warm" (analysis only), "cold" (summary only)
      add :storage_tier, :string, default: "hot"
    end
  end
end
