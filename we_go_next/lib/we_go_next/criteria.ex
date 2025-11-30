defmodule WeGoNext.Criteria do
  @moduledoc """
  Context module for managing mechanic criteria.

  Criteria define what abilities to track as mechanics and how to detect failures.

  ## Difficulty Inheritance

  Criteria can be set at different difficulty levels:
  - Global (nil boss_encounter_id) - applies to all bosses
  - Boss-specific with no difficulty (nil difficulty_id) - applies to all difficulties of that boss
  - Boss + difficulty specific - applies only to that difficulty

  Higher difficulties inherit from lower:
  - Mythic (16) inherits from Heroic (15) and Normal (14)
  - Heroic (15) inherits from Normal (14)

  When looking up criteria, we return the most specific match.
  """

  import Ecto.Query
  alias WeGoNext.Repo
  alias WeGoNext.Criteria.MechanicCriteria

  # WoW difficulty IDs
  @normal 14
  @heroic 15
  @mythic 16

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
  Returns criteria for a specific boss encounter with difficulty inheritance.

  Includes:
  - Global criteria (nil boss_encounter_id)
  - Boss-specific criteria for all difficulties (nil difficulty_id)
  - Boss + difficulty specific criteria for this and lower difficulties

  For each spell, returns the most specific criteria (higher difficulty takes precedence).
  """
  def list_criteria_for_boss(boss_encounter_id, difficulty_id \\ nil) do
    inherited_difficulties = inherited_difficulty_ids(difficulty_id)

    MechanicCriteria
    |> where([c], c.active == true)
    |> where(
      [c],
      # Global criteria
      is_nil(c.boss_encounter_id) or
        # Boss-specific criteria
        (c.boss_encounter_id == ^boss_encounter_id and
           (is_nil(c.difficulty_id) or c.difficulty_id in ^inherited_difficulties))
    )
    |> order_by([c], [asc: c.spell_name])
    |> Repo.all()
    |> dedupe_by_specificity()
  end

  # Returns difficulty IDs that should be inherited (this difficulty and lower)
  defp inherited_difficulty_ids(nil), do: [@normal, @heroic, @mythic]
  defp inherited_difficulty_ids(@mythic), do: [@normal, @heroic, @mythic]
  defp inherited_difficulty_ids(@heroic), do: [@normal, @heroic]
  defp inherited_difficulty_ids(@normal), do: [@normal]
  defp inherited_difficulty_ids(_other), do: [@normal, @heroic, @mythic]

  # For each spell, keep only the most specific criteria
  # Priority: boss+difficulty > boss only > global
  defp dedupe_by_specificity(criteria_list) do
    criteria_list
    |> Enum.group_by(& &1.spell_id)
    |> Enum.flat_map(fn {_spell_id, criteria_for_spell} ->
      # Sort by specificity (most specific first) and take the first
      criteria_for_spell
      |> Enum.sort_by(&specificity_score/1, :desc)
      |> Enum.take(1)
    end)
  end

  # Higher score = more specific
  defp specificity_score(%MechanicCriteria{boss_encounter_id: nil}), do: 0
  defp specificity_score(%MechanicCriteria{difficulty_id: nil}), do: 1
  defp specificity_score(%MechanicCriteria{difficulty_id: @normal}), do: 2
  defp specificity_score(%MechanicCriteria{difficulty_id: @heroic}), do: 3
  defp specificity_score(%MechanicCriteria{difficulty_id: @mythic}), do: 4
  defp specificity_score(_), do: 1

  @doc """
  Returns criteria matching a specific spell ID.
  """
  def get_criteria_for_spell(spell_id, boss_encounter_id \\ nil, difficulty_id \\ nil) do
    inherited_difficulties = inherited_difficulty_ids(difficulty_id)

    MechanicCriteria
    |> where([c], c.spell_id == ^spell_id and c.active == true)
    |> where(
      [c],
      is_nil(c.boss_encounter_id) or
        (c.boss_encounter_id == ^boss_encounter_id and
           (is_nil(c.difficulty_id) or c.difficulty_id in ^inherited_difficulties))
    )
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
  Checks if a spell is already tracked as a criteria for the given boss/difficulty.
  """
  def spell_tracked?(spell_id, boss_encounter_id \\ nil, difficulty_id \\ nil) do
    query =
      MechanicCriteria
      |> where([c], c.spell_id == ^spell_id)

    query =
      if boss_encounter_id do
        where(query, [c], c.boss_encounter_id == ^boss_encounter_id or is_nil(c.boss_encounter_id))
      else
        where(query, [c], is_nil(c.boss_encounter_id))
      end

    query =
      if difficulty_id do
        where(query, [c], c.difficulty_id == ^difficulty_id or is_nil(c.difficulty_id))
      else
        query
      end

    Repo.exists?(query)
  end

  @doc """
  Returns a map of spell_id => [criteria] for quick lookup during analysis.
  Supports difficulty inheritance.
  """
  def criteria_by_spell_id(boss_encounter_id \\ nil, difficulty_id \\ nil) do
    list_criteria_for_boss(boss_encounter_id, difficulty_id)
    |> Enum.group_by(& &1.spell_id)
  end
end
