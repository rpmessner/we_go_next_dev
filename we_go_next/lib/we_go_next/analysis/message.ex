defmodule WeGoNext.Analysis.Message do
  @moduledoc "Append-only Messages API content, preserving signed thinking and Tool blocks."
  use Ecto.Schema
  @schema_prefix "analysis"
  schema "messages" do
    field(:session_id, :binary_id)
    field(:question_id, :binary_id)
    field(:role, :string)
    field(:content, {:array, :map})
    field(:usage, :map, default: %{})
    field(:stop_reason, :string)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
