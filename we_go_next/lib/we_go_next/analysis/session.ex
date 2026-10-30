defmodule WeGoNext.Analysis.Session do
  @moduledoc "Durable Analysis session identity, independent of MCP connections."
  use Ecto.Schema
  @schema_prefix "analysis"
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "sessions" do
    field(:started_at, :utc_datetime_usec)
    field(:combat_log_file_id, :id)
    field(:boss, :string)
    field(:model, :string, default: "claude-opus-5-5")
    field(:loaded_playbooks, {:array, :map}, default: [])
    field(:playbooks, {:array, :map}, virtual: true, default: [])
  end
end
