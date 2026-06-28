defmodule WeGoNext.Mirror.PublicReport do
  @moduledoc """
  Public share/report that scopes mirrored gold data behind one URL slug.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "public_reports" do
    field(:slug, :string)
    field(:title, :string)
    field(:enabled, :boolean, default: true)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(public_report, attrs) do
    public_report
    |> cast(attrs, [:slug, :title, :enabled])
    |> validate_required([:slug, :title, :enabled])
    |> validate_format(:slug, ~r/^[A-Za-z0-9][A-Za-z0-9_-]{2,127}$/)
    |> unique_constraint(:slug)
  end
end
