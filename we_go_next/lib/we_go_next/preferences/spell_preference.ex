defmodule WeGoNext.Preferences.SpellPreference do
  @moduledoc """
  Tracks per-encounter spell visibility preferences.

  Admins can hide specific spells from the debuffs tab for a given encounter.
  This allows filtering out noise from boss mechanics that aren't useful to track.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "spell_preferences" do
    field :spell_id, :integer
    field :spell_name, :string
    field :encounter_id, :integer
    field :hidden, :boolean, default: false
    field :force_show, :boolean, default: false

    timestamps()
  end

  @doc false
  def changeset(spell_preference, attrs) do
    spell_preference
    |> cast(attrs, [:spell_id, :spell_name, :encounter_id, :hidden, :force_show])
    |> validate_required([:spell_id, :spell_name, :encounter_id])
    |> unique_constraint([:spell_id, :encounter_id])
  end
end
