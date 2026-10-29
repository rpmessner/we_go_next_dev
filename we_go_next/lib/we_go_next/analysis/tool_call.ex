defmodule WeGoNext.Analysis.ToolCall do
  @moduledoc "The bounded full result returned to the model, including rejected calls."
  use Ecto.Schema
  @schema_prefix "analysis"
  schema "tool_calls" do
    field(:session_id, :binary_id)
    field(:tool, :string)
    field(:args, :map)
    field(:result, :map)
    field(:result_size, :integer)
    field(:duration_ms, :integer)
    field(:truncated, :boolean)
    field(:error, :string)
    field(:called_at, :utc_datetime_usec)
  end
end
