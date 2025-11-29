defmodule WeGoNext.Repo.Migrations.AddIsAdminToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_admin, :boolean, default: false, null: false
    end

    # Make the existing default user an admin
    execute "UPDATE users SET is_admin = true WHERE name = 'default'", ""
  end
end
