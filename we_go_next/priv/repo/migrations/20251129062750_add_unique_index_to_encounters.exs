defmodule WeGoNext.Repo.Migrations.AddUniqueIndexToEncounters do
  use Ecto.Migration

  def up do
    # First, remove duplicate encounters keeping only the first (lowest id) for each
    # combat_log_file_id + start_time combination
    execute """
    DELETE FROM encounter_events
    WHERE encounter_id IN (
      SELECT e.id FROM encounters e
      WHERE e.id NOT IN (
        SELECT MIN(id)
        FROM encounters
        GROUP BY combat_log_file_id, start_time
      )
    )
    """

    execute """
    DELETE FROM encounters
    WHERE id NOT IN (
      SELECT MIN(id)
      FROM encounters
      GROUP BY combat_log_file_id, start_time
    )
    """

    # Now create the unique index
    create unique_index(:encounters, [:combat_log_file_id, :start_time],
      name: :encounters_combat_log_file_id_start_time_index
    )
  end

  def down do
    drop index(:encounters, [:combat_log_file_id, :start_time],
      name: :encounters_combat_log_file_id_start_time_index
    )
  end
end
