defmodule WeGoNext.Gold.DimEncounter do
  @moduledoc """
  Gold dimension row for encounter metadata.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.Mirror.Keys

  @schema_prefix "gold"

  @type t :: %__MODULE__{}

  schema "dim_encounter" do
    field(:source_encounter_key, :string)
    field(:source_file_path, :string)
    field(:source_head_sha256, :string)
    field(:wow_encounter_id, :string)
    field(:name, :string)
    field(:difficulty_id, :integer)
    field(:difficulty_name, :string)
    field(:group_size, :integer)
    field(:instance_id, :string)
    field(:start_time, :utc_datetime_usec)
    field(:end_time, :utc_datetime_usec)
    field(:success, :boolean)
    field(:fight_time_ms, :integer)
    field(:start_byte, :integer)
    field(:end_byte, :integer)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(dim_encounter, attrs) do
    dim_encounter
    |> cast(attrs, [
      :source_file_path,
      :source_encounter_key,
      :source_head_sha256,
      :wow_encounter_id,
      :name,
      :difficulty_id,
      :difficulty_name,
      :group_size,
      :instance_id,
      :start_time,
      :end_time,
      :success,
      :fight_time_ms,
      :start_byte,
      :end_byte
    ])
    |> put_source_encounter_key()
    |> validate_required([:wow_encounter_id, :name])
    |> unique_constraint(:source_encounter_key,
      name: :dim_encounter_source_encounter_key_parser_index
    )
  end

  defp put_source_encounter_key(changeset) do
    if get_field(changeset, :source_encounter_key) do
      changeset
    else
      key =
        changeset
        |> fields_for_key()
        |> Keys.source_encounter_key()

      if key, do: put_change(changeset, :source_encounter_key, key), else: changeset
    end
  end

  defp fields_for_key(changeset) do
    %{
      source_head_sha256: get_field(changeset, :source_head_sha256),
      start_byte: get_field(changeset, :start_byte),
      end_byte: get_field(changeset, :end_byte),
      wow_encounter_id: get_field(changeset, :wow_encounter_id),
      start_time: get_field(changeset, :start_time)
    }
  end
end
