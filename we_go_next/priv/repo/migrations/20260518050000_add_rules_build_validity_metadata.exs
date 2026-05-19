defmodule WeGoNext.Repo.Migrations.AddRulesBuildValidityMetadata do
  use Ecto.Migration

  def up do
    alter table(:ruleset, prefix: "rules") do
      add(:product, :string, null: false, default: "wow")
      add(:channel, :string, null: false, default: "retail")
      add(:build_version, :string)
      add(:build_key, :string)
    end

    create(index(:ruleset, [:product, :channel, :build_key], prefix: "rules"))

    alter table(:dbm_mechanic_candidate, prefix: "source_data") do
      add(:product, :string, null: false, default: "wow")
      add(:channel, :string, null: false, default: "retail")
      add(:build_version, :string)
      add(:build_key, :string)
    end

    create(
      index(:dbm_mechanic_candidate, [:product, :channel, :build_key],
        prefix: "source_data",
        name: :dbm_mechanic_candidate_build_scope_index
      )
    )

    alter table(:dim_mechanic_criterion, prefix: "gold") do
      add(:product, :string, null: false, default: "wow")
      add(:channel, :string, null: false, default: "retail")
      add(:build_version, :string)
      add(:build_key, :string)
    end

    create(
      index(:dim_mechanic_criterion, [:ruleset_id, :product, :channel, :build_key],
        prefix: "gold",
        name: :dim_mechanic_criterion_ruleset_build_scope_index
      )
    )

    alter table(:fact_failure, prefix: "gold") do
      add(:ruleset_id, :bigint)
      add(:ruleset_version, :integer)
      add(:product, :string, null: false, default: "wow")
      add(:channel, :string, null: false, default: "retail")
      add(:build_version, :string)
      add(:build_key, :string)
    end

    execute("""
    UPDATE gold.fact_failure AS fact
    SET
      ruleset_id = criterion.ruleset_id,
      ruleset_version = criterion.ruleset_version,
      product = criterion.product,
      channel = criterion.channel,
      build_version = criterion.build_version,
      build_key = criterion.build_key
    FROM gold.dim_mechanic_criterion AS criterion
    WHERE criterion.id = fact.criterion_dim_id
    """)

    execute("ALTER TABLE gold.fact_failure ALTER COLUMN ruleset_id SET NOT NULL")
    execute("ALTER TABLE gold.fact_failure ALTER COLUMN ruleset_version SET NOT NULL")

    create(
      index(:fact_failure, [:ruleset_id, :product, :channel, :build_key],
        prefix: "gold",
        name: :fact_failure_ruleset_build_scope_index
      )
    )
  end

  def down do
    drop(
      index(:fact_failure, [:ruleset_id, :product, :channel, :build_key],
        prefix: "gold",
        name: :fact_failure_ruleset_build_scope_index
      )
    )

    alter table(:fact_failure, prefix: "gold") do
      remove(:build_key)
      remove(:build_version)
      remove(:channel)
      remove(:product)
      remove(:ruleset_version)
      remove(:ruleset_id)
    end

    drop(
      index(:dim_mechanic_criterion, [:ruleset_id, :product, :channel, :build_key],
        prefix: "gold",
        name: :dim_mechanic_criterion_ruleset_build_scope_index
      )
    )

    alter table(:dim_mechanic_criterion, prefix: "gold") do
      remove(:build_key)
      remove(:build_version)
      remove(:channel)
      remove(:product)
    end

    drop(
      index(:dbm_mechanic_candidate, [:product, :channel, :build_key],
        prefix: "source_data",
        name: :dbm_mechanic_candidate_build_scope_index
      )
    )

    alter table(:dbm_mechanic_candidate, prefix: "source_data") do
      remove(:build_key)
      remove(:build_version)
      remove(:channel)
      remove(:product)
    end

    drop(index(:ruleset, [:product, :channel, :build_key], prefix: "rules"))

    alter table(:ruleset, prefix: "rules") do
      remove(:build_key)
      remove(:build_version)
      remove(:channel)
      remove(:product)
    end
  end
end
