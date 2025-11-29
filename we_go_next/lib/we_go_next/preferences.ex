defmodule WeGoNext.Preferences do
  @moduledoc """
  Context for managing user preferences, including spell visibility settings.
  """

  import Ecto.Query
  alias WeGoNext.Repo
  alias WeGoNext.Preferences.SpellPreference

  @doc """
  Returns a map of spell_id => %SpellPreference{} for a given encounter.
  """
  def get_spell_preferences(encounter_id) do
    SpellPreference
    |> where([sp], sp.encounter_id == ^encounter_id)
    |> Repo.all()
    |> Map.new(fn pref -> {pref.spell_id, pref} end)
  end

  @doc """
  Returns a MapSet of hidden spell IDs for a given encounter.
  """
  def hidden_spell_ids(encounter_id) do
    SpellPreference
    |> where([sp], sp.encounter_id == ^encounter_id and sp.hidden == true)
    |> select([sp], sp.spell_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Toggles the hidden status for a spell in an encounter.
  Creates the preference if it doesn't exist.
  """
  def toggle_spell_visibility(encounter_id, spell_id, spell_name) do
    case Repo.get_by(SpellPreference, encounter_id: encounter_id, spell_id: spell_id) do
      nil ->
        # Create as hidden (toggling from default visible to hidden)
        %SpellPreference{}
        |> SpellPreference.changeset(%{
          encounter_id: encounter_id,
          spell_id: spell_id,
          spell_name: spell_name,
          hidden: true
        })
        |> Repo.insert()

      pref ->
        # Toggle existing preference
        pref
        |> SpellPreference.changeset(%{hidden: !pref.hidden})
        |> Repo.update()
    end
  end

  @doc """
  Sets the hidden status for a spell in an encounter.
  """
  def set_spell_hidden(encounter_id, spell_id, spell_name, hidden) do
    case Repo.get_by(SpellPreference, encounter_id: encounter_id, spell_id: spell_id) do
      nil ->
        %SpellPreference{}
        |> SpellPreference.changeset(%{
          encounter_id: encounter_id,
          spell_id: spell_id,
          spell_name: spell_name,
          hidden: hidden
        })
        |> Repo.insert()

      pref ->
        pref
        |> SpellPreference.changeset(%{hidden: hidden})
        |> Repo.update()
    end
  end

  @doc """
  Checks if a spell is hidden for an encounter.
  """
  def spell_hidden?(encounter_id, spell_id) do
    SpellPreference
    |> where([sp], sp.encounter_id == ^encounter_id and sp.spell_id == ^spell_id and sp.hidden == true)
    |> Repo.exists?()
  end

  @doc """
  Returns a MapSet of force-shown spell IDs for a given encounter.
  These spells will always be shown regardless of the player debuffs toggle.
  """
  def force_shown_spell_ids(encounter_id) do
    SpellPreference
    |> where([sp], sp.encounter_id == ^encounter_id and sp.force_show == true)
    |> select([sp], sp.spell_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Toggles the force_show status for a spell in an encounter.
  Creates the preference if it doesn't exist.
  """
  def toggle_force_show(encounter_id, spell_id, spell_name) do
    case Repo.get_by(SpellPreference, encounter_id: encounter_id, spell_id: spell_id) do
      nil ->
        # Create as force-shown (toggling from default to force-shown)
        %SpellPreference{}
        |> SpellPreference.changeset(%{
          encounter_id: encounter_id,
          spell_id: spell_id,
          spell_name: spell_name,
          force_show: true
        })
        |> Repo.insert()

      pref ->
        # Toggle existing preference
        pref
        |> SpellPreference.changeset(%{force_show: !pref.force_show})
        |> Repo.update()
    end
  end
end
