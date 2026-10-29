defmodule WeGoNext.Analysis.Tool do
  @moduledoc """
  Read-only Analysis Tool contract. `run/2` receives JSON args (string keys) and
  a persisted Analysis.Session. Return `{:ok, envelope}` or `{:error, short_reason}`.
  Use Result.page/5 for bounded, deterministic pagination. Never write files or
  mutate data; the executor enforces DB read-only and a five-second deadline.
  The operator-approved StartSession Tool alone receives nil and may create its
  Analysis session; all evidence Tools still receive a persisted Session.
  """
  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback input_schema() :: map()
  @callback run(map(), map()) :: {:ok, map()} | {:error, String.t()}

  def schema(properties \\ %{}) do
    %{
      "type" => "object",
      "properties" =>
        Map.merge(
          %{
            "session_id" => %{"type" => "string", "format" => "uuid"},
            "cursor" => %{"type" => "string"}
          },
          properties
        ),
      "required" => ["session_id"],
      "additionalProperties" => false
    }
  end
end
