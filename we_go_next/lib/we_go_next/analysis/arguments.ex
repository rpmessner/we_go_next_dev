defmodule WeGoNext.Analysis.Arguments do
  @moduledoc """
  Validates the Tool JSON Schema subset: object, array, string, integer, number,
  boolean, null, enum, required, additionalProperties, items, min/maxItems,
  minimum/maximum, min/maxLength and uuid/date formats. Unknown types fail closed.
  Tools needing other schema keywords must extend this validator with tests.
  """
  def validate(args, schema) do
    if matches?(args, schema),
      do: :ok,
      else: {:error, "Invalid Tool arguments; follow inputSchema"}
  end

  defp matches?(value, schema) do
    enum?(value, schema) and type?(value, schema)
  end

  defp enum?(value, %{"enum" => allowed}), do: value in allowed
  defp enum?(_, _), do: true

  defp type?(value, %{"type" => "object"} = schema) when is_map(value) do
    properties = Map.get(schema, "properties", %{})

    Enum.all?(Map.get(schema, "required", []), &Map.has_key?(value, &1)) and
      Enum.all?(value, fn {key, v} -> property?(v, Map.get(properties, key), schema) end)
  end

  defp type?(value, %{"type" => "array"} = schema) when is_list(value) do
    bounds?(length(value), schema, "minItems", "maxItems") and
      Enum.all?(value, &matches?(&1, Map.get(schema, "items", %{})))
  end

  defp type?(value, %{"type" => "string"} = schema) when is_binary(value) do
    bounds?(String.length(value), schema, "minLength", "maxLength") and format?(value, schema)
  end

  defp type?(value, %{"type" => "integer"} = schema) when is_integer(value),
    do: number?(value, schema)

  defp type?(value, %{"type" => "number"} = schema) when is_number(value),
    do: number?(value, schema)

  defp type?(value, %{"type" => "boolean"}) when is_boolean(value), do: true
  defp type?(nil, %{"type" => "null"}), do: true
  defp type?(_, schema), do: schema == %{}

  defp property?(value, schema, _) when is_map(schema), do: matches?(value, schema)
  defp property?(_, nil, %{"additionalProperties" => false}), do: false

  defp property?(value, nil, %{"additionalProperties" => schema}) when is_map(schema),
    do: matches?(value, schema)

  defp property?(_, _, _), do: true

  defp number?(value, schema), do: bounds?(value, schema, "minimum", "maximum")

  defp bounds?(value, schema, min_key, max_key) do
    (not Map.has_key?(schema, min_key) or value >= schema[min_key]) and
      (not Map.has_key?(schema, max_key) or value <= schema[max_key])
  end

  defp format?(value, %{"format" => "uuid"}), do: match?({:ok, _}, Ecto.UUID.cast(value))
  defp format?(value, %{"format" => "date"}), do: match?({:ok, _}, Date.from_iso8601(value))
  defp format?(_, _), do: true
end
