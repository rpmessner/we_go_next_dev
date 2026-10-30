defmodule WeGoNext.Analysis.Question do
  @moduledoc "One scoped question in an Analysis session, with a durable lifecycle snapshot."
  use Ecto.Schema
  @schema_prefix "analysis"
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "questions" do
    field(:session_id, :binary_id)
    field(:scope, :map, default: %{})
    field(:text, :string)
    field(:model, :string)
    field(:state, :string, default: "draft")
    field(:lifecycle, :map, default: %{})
    field(:answer, :string)
    field(:error, :string)
    timestamps(type: :utc_datetime_usec)
  end
end
