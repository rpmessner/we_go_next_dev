defmodule WeGoNext.Criteria do
  @moduledoc """
  Context module for managing mechanic criteria.

  Criteria define what abilities to track as mechanics and how to detect failures.
  """

  import Ecto.Query
  alias WeGoNext.Repo
  alias WeGoNext.Criteria.MechanicCriteria

  @doc """
  Returns all active criteria.
  """
  def list_criteria do
    MechanicCriteria
    |> where([c], c.active == true)
    |> order_by([c], [asc: c.boss_name, asc: c.spell_name])
    |> Repo.all()
  end

  @doc """
  Returns all criteria (including inactive).
  """
  def list_all_criteria do
    MechanicCriteria
    |> order_by([c], [asc: c.boss_name, asc: c.spell_name])
    |> Repo.all()
  end

  @doc """
  Returns criteria for a specific boss encounter.
  Returns both boss-specific and global criteria.
  """
  def list_criteria_for_boss(boss_encounter_id) do
    MechanicCriteria
    |> where([c], c.active == true)
    |> where([c], is_nil(c.boss_encounter_id) or c.boss_encounter_id == ^boss_encounter_id)
    |> order_by([c], [asc: c.spell_name])
    |> Repo.all()
  end

  @doc """
  Returns criteria matching a specific spell ID.
  """
  def get_criteria_for_spell(spell_id, boss_encounter_id \\ nil) do
    MechanicCriteria
    |> where([c], c.spell_id == ^spell_id and c.active == true)
    |> where([c], is_nil(c.boss_encounter_id) or c.boss_encounter_id == ^boss_encounter_id)
    |> Repo.all()
  end

  @doc """
  Gets a single criteria by ID.
  """
  def get_criteria!(id) do
    Repo.get!(MechanicCriteria, id)
  end

  @doc """
  Gets a single criteria by ID, returns nil if not found.
  """
  def get_criteria(id) do
    Repo.get(MechanicCriteria, id)
  end

  @doc """
  Creates a new mechanic criteria.
  """
  def create_criteria(attrs \\ %{}) do
    %MechanicCriteria{}
    |> MechanicCriteria.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a mechanic criteria.
  """
  def update_criteria(%MechanicCriteria{} = criteria, attrs) do
    criteria
    |> MechanicCriteria.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a mechanic criteria.
  """
  def delete_criteria(%MechanicCriteria{} = criteria) do
    Repo.delete(criteria)
  end

  @doc """
  Toggles the active status of a criteria.
  """
  def toggle_criteria(%MechanicCriteria{} = criteria) do
    update_criteria(criteria, %{active: !criteria.active})
  end

  @doc """
  Returns a changeset for tracking changes.
  """
  def change_criteria(%MechanicCriteria{} = criteria, attrs \\ %{}) do
    MechanicCriteria.changeset(criteria, attrs)
  end

  @doc """
  Checks if a spell is already tracked as a criteria.
  """
  def spell_tracked?(spell_id, boss_encounter_id \\ nil) do
    query =
      MechanicCriteria
      |> where([c], c.spell_id == ^spell_id)

    query =
      if boss_encounter_id do
        where(query, [c], c.boss_encounter_id == ^boss_encounter_id or is_nil(c.boss_encounter_id))
      else
        where(query, [c], is_nil(c.boss_encounter_id))
      end

    Repo.exists?(query)
  end

  @doc """
  Returns a map of spell_id => criteria for quick lookup during analysis.
  """
  def criteria_by_spell_id(boss_encounter_id \\ nil) do
    list_criteria_for_boss(boss_encounter_id)
    |> Enum.group_by(& &1.spell_id)
  end
end
