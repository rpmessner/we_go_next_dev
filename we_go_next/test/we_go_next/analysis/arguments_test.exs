defmodule WeGoNext.Analysis.ArgumentsTest do
  use ExUnit.Case, async: true
  alias WeGoNext.Analysis.Arguments

  test "validates the JSON types later Tools need without converting input keys to atoms" do
    schema = %{
      "type" => "object",
      "required" => ["pulls"],
      "additionalProperties" => false,
      "properties" => %{
        "pulls" => %{
          "type" => "array",
          "items" => %{"type" => "integer", "minimum" => 1},
          "minItems" => 1
        },
        "filter" => %{
          "type" => "object",
          "additionalProperties" => false,
          "properties" => %{"enabled" => %{"type" => "boolean"}}
        },
        "ratio" => %{"type" => "number", "maximum" => 1},
        "mode" => %{"type" => "string", "enum" => ["boss", "night"]}
      }
    }

    assert :ok =
             Arguments.validate(
               %{
                 "pulls" => [1, 2],
                 "filter" => %{"enabled" => true},
                 "ratio" => 0.5,
                 "mode" => "boss"
               },
               schema
             )

    for args <- [
          %{},
          %{"pulls" => []},
          %{"pulls" => ["1"]},
          %{"pulls" => [0]},
          %{"pulls" => [1], "unknown" => 1},
          %{"pulls" => [1], "mode" => "other"},
          %{"pulls" => [1], "ratio" => 2}
        ] do
      assert {:error, _} = Arguments.validate(args, schema)
    end
  end

  test "string formats and required properties are checked" do
    schema = %{
      "type" => "object",
      "required" => ["session_id"],
      "properties" => %{
        "session_id" => %{"type" => "string", "format" => "uuid"},
        "night" => %{"type" => "string", "format" => "date"}
      }
    }

    assert :ok =
             Arguments.validate(
               %{"session_id" => Ecto.UUID.generate(), "night" => "2026-09-06"},
               schema
             )

    assert {:error, _} = Arguments.validate(%{"session_id" => "bad"}, schema)

    assert {:error, _} =
             Arguments.validate(
               %{"session_id" => Ecto.UUID.generate(), "night" => "2026-99-01"},
               schema
             )
  end
end
