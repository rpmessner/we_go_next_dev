defmodule WeGoNext.Mirror.Keys do
  @moduledoc """
  Deterministic opaque keys for parser/public gold mirroring.
  """

  alias WeGoNext.Gold.FactFailure.Semantics

  @separator <<31>>

  @doc """
  Computes the public source encounter key from byte-range source identity.

  Returns `nil` if any required identity input is missing; publishing such an
  encounter is an error handled by the snapshot/upload boundary.
  """
  @spec source_encounter_key(map()) :: String.t() | nil
  def source_encounter_key(attrs) when is_map(attrs) do
    values = [
      fetch(attrs, :source_head_sha256),
      fetch(attrs, :start_byte),
      fetch(attrs, :end_byte),
      fetch(attrs, :wow_encounter_id),
      fetch(attrs, :start_time)
    ]

    if Enum.all?(values, &present?/1) do
      values
      |> Enum.map(&normalize_value/1)
      |> hash_values()
    end
  end

  @doc """
  Computes the stable public key for a mechanic criterion snapshot.
  """
  @spec criterion_key(map(), keyword()) :: String.t()
  def criterion_key(attrs, opts \\ []) when is_map(attrs) do
    semantics_version =
      Keyword.get_lazy(opts, :semantics_version, fn ->
        attrs
        |> fetch(:mechanic_type)
        |> Semantics.version_for!()
      end)

    criterion_semantics_hash =
      hash_values([
        canonical_json(fetch(attrs, :threshold) || %{}),
        semantics_version
      ])

    [
      fetch(attrs, :product),
      fetch(attrs, :channel),
      fetch(attrs, :build_key),
      fetch(attrs, :boss_encounter_id),
      fetch(attrs, :difficulty_id),
      fetch(attrs, :spell_id),
      fetch(attrs, :mechanic_type),
      criterion_semantics_hash
    ]
    |> Enum.map(&normalize_value/1)
    |> hash_values()
  end

  @doc """
  Computes the threshold + semantics-version hash embedded in criterion identity.
  """
  @spec criterion_semantics_hash(map(), keyword()) :: String.t()
  def criterion_semantics_hash(attrs, opts \\ []) when is_map(attrs) do
    semantics_version =
      Keyword.get_lazy(opts, :semantics_version, fn ->
        attrs
        |> fetch(:mechanic_type)
        |> Semantics.version_for!()
      end)

    hash_values([canonical_json(fetch(attrs, :threshold) || %{}), semantics_version])
  end

  defp hash_values(values) do
    values
    |> Enum.map(&normalize_value/1)
    |> Enum.join(@separator)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonical_json(value) when is_map(value) do
    value
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Map.new(fn {key, value} -> {to_string(key), canonicalize(value)} end)
    |> Jason.encode!()
  end

  defp canonical_json(value), do: value |> canonicalize() |> Jason.encode!()

  defp canonicalize(value) when is_map(value) do
    value
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Map.new(fn {key, value} -> {to_string(key), canonicalize(value)} end)
  end

  defp canonicalize(value) when is_list(value), do: Enum.map(value, &canonicalize/1)
  defp canonicalize(value), do: value

  defp fetch(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp normalize_value(nil), do: ""
  defp normalize_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp normalize_value(value) when is_binary(value), do: value
  defp normalize_value(value), do: to_string(value)

  defp present?(nil), do: false
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: true
end
