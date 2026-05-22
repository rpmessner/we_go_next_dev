defmodule WeGoNext.Repo.Migrations.AddFactFailureDerivationMetadata do
  use Ecto.Migration

  def change do
    alter table(:fact_failure, prefix: "gold") do
      add(:derivation_version, :integer)
      add(:rebuilt_at, :utc_datetime_usec)
    end

    create(index(:fact_failure, [:derivation_version], prefix: "gold"))
    create(index(:fact_failure, [:rebuilt_at], prefix: "gold"))
  end
end
