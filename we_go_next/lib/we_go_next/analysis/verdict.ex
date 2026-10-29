defmodule WeGoNext.Analysis.Verdict do
  @moduledoc "An indefinitely retained operator judgment linked to its Analysis session and answer."
  use Ecto.Schema
  @schema_prefix "analysis"
  schema "verdicts" do
    field(:session_id, :binary_id)
    field(:answer, :string)
    field(:verdict, :string)
    field(:correction, :string)
    field(:recorded_at, :utc_datetime_usec)
  end
end
