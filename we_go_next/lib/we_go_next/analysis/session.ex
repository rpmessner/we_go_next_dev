defmodule WeGoNext.Analysis.Session do
  @moduledoc "Durable Analysis session identity, independent of MCP connections."
  use Ecto.Schema
  @schema_prefix "analysis"
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "sessions" do
    field(:started_at, :utc_datetime_usec)
    field(:combat_log_file_id, :id)
    field(:boss, :string)
  end
end
