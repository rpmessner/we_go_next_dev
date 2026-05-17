defmodule WeGoNext.Gold.DimEncounter do
  @moduledoc """
  Gold dimension row for encounter metadata.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @schema_prefix "gold"

  @type t :: %__MODULE__{}

  schema "dim_encounter" do
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
    |> validate_required([:wow_encounter_id, :name])
  end
end
