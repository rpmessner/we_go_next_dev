defmodule WeGoNext.Analyzers.AnalysisCache do
  @moduledoc """
  Pre-computes and caches encounter analysis for fast loading.

  This module provides the public API for analysis caching:
  - `compute/1` - Runs all analyzers and returns a JSON-serializable map
  - `serialize/1` - Converts pre-computed analysis to JSON format
  - `from_cache/1` - Restores cached analysis to UI-friendly format

  The actual serialization and deserialization logic is delegated to:
  - `AnalysisCache.Serializer` - Struct → JSON map conversion
  - `AnalysisCache.Deserializer` - JSON map → atom-keyed map conversion
  """

  alias __MODULE__.{Serializer, Deserializer}

  @doc """
  Generates complete analysis for an encounter, returning a JSON-serializable map.

  Runs all analyzers (death, damage, interrupt, debuff, failure, summary) and
  serializes the results to a format suitable for database storage.
  """
  defdelegate compute(encounter), to: Serializer

  @doc """
  Serializes pre-computed analysis data to a JSON-friendly map.

  Use this when you've already computed analysis and just need to convert
  it for storage. The input should be a map with keys:
  - `:deaths`
  - `:damage_stats`
  - `:damage_done`
  - `:interrupt_stats`
  - `:debuff_stats`
  - `:failure_stats`
  - `:summary`
  - `:player_classes` (optional)
  """
  defdelegate serialize(data), to: Serializer

  @doc """
  Converts cached analysis map back to the format expected by the UI.

  Transforms string keys to atoms and handles:
  - Missing keys with sensible defaults
  - DateTime parsing from ISO8601 strings
  - Building derived structures

  Returns `nil` if cache is nil or empty.
  """
  defdelegate from_cache(cache), to: Deserializer
end
