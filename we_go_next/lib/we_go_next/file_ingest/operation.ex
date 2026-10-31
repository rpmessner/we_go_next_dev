defmodule WeGoNext.FileIngest.Operation do
  @moduledoc "Durable user-facing import receipt; tokens fence late task results."
  use Ecto.Schema

  schema "import_operations" do
    field(:user_id, :integer)
    field(:token, Ecto.UUID)
    field(:path, :string)
    field(:status, :string)
    field(:started_at, :utc_datetime_usec)
    field(:deadline, :utc_datetime_usec)
    field(:error, :string)
    field(:encounters, :integer)
  end
end
