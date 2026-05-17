defmodule WeGoNext.Repo.Migrations.CreateGoldDimPlayer do
  use Ecto.Migration

  def change do
    create table(:dim_player, prefix: "gold") do
      add(:player_guid, :string, null: false)
      add(:player_name, :string, null: false)
      add(:class_id, :integer)
      add(:spec_id, :integer)
      add(:inserted_at, :utc_datetime_usec, null: false, default: fragment("now()"))
      add(:updated_at, :utc_datetime_usec, null: false, default: fragment("now()"))
    end

    create(unique_index(:dim_player, [:player_guid], prefix: "gold"))
  end
end
