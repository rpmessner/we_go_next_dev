defmodule WeGoNext.Mirror.MirrorUpload do
  @moduledoc """
  Parser-side public mirror upload outbox row.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @states ~w(pending published stale error)

  schema "mirror_uploads" do
    field(:source_encounter_key, :string)
    field(:state, :string, default: "pending")
    field(:last_error, :string)
    field(:published_at, :utc_datetime_usec)
    field(:attempt_count, :integer, default: 0)
    field(:last_attempted_at, :utc_datetime_usec)
    field(:batch_id, :string)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(upload, attrs) do
    upload
    |> cast(attrs, [
      :source_encounter_key,
      :state,
      :last_error,
      :published_at,
      :attempt_count,
      :last_attempted_at,
      :batch_id
    ])
    |> validate_required([:source_encounter_key, :state])
    |> validate_inclusion(:state, @states)
    |> unique_constraint(:source_encounter_key)
  end

  def states, do: @states
end
