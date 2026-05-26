defmodule WeGoNext.Repo.Migrations.AddRulesetSeedUniqueness do
  use Ecto.Migration

  def change do
    create(
      unique_index(:ruleset, [:name, :version],
        prefix: "rules",
        name: :ruleset_name_version_index
      )
    )
  end
end
