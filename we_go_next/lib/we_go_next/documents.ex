defmodule WeGoNext.Documents do
  @moduledoc """
  Builds and persists JSON encounter documents for the frontend render path.
  """

  import Ecto.Query

  alias WeGoNext.Documents.{EncounterDocument, Store}
  alias WeGoNext.Gold.DimEncounter
  alias WeGoNext.Gold.FactFailure.Derivation
  alias WeGoNext.Repo

  @type generate_result :: %{
          source_encounter_key: String.t(),
          encounter_path: String.t(),
          index_path: String.t()
        }

  @doc """
  Generates and writes one encounter document, then refreshes `index.json`.
  """
  @spec generate_for_encounter(pos_integer() | DimEncounter.t(), keyword()) ::
          {:ok, generate_result()} | {:error, term()}
  def generate_for_encounter(encounter_or_id, opts \\ [])

  def generate_for_encounter(%DimEncounter{id: id}, opts), do: generate_for_encounter(id, opts)

  def generate_for_encounter(encounter_dim_id, opts)
      when is_integer(encounter_dim_id) and is_list(opts) do
    with {:ok, document} <- EncounterDocument.encode(encounter_dim_id, opts),
         store = Store.configured_module(opts),
         {:ok, encounter_path} <- put_json(store, encounter_key(document), document),
         {:ok, index_path} <- refresh_index(store, document) do
      {:ok,
       %{
         source_encounter_key: document.source_encounter_key,
         encounter_path: encounter_path,
         index_path: index_path
       }}
    end
  end

  @doc """
  Generates documents for every known gold encounter.
  """
  @spec rebuild_all(keyword()) :: {:ok, %{encounters: non_neg_integer()}} | {:error, map()}
  def rebuild_all(opts \\ []) do
    rebuild_encounters(encounter_ids(opts), opts)
  end

  @doc """
  Generates documents for the given gold encounter ids.
  """
  @spec rebuild_encounters([pos_integer()], keyword()) ::
          {:ok, %{encounters: non_neg_integer()}} | {:error, map()}
  def rebuild_encounters(encounter_ids, opts \\ []) when is_list(encounter_ids) do
    totals = %{encounters: 0}

    Enum.reduce_while(encounter_ids, {:ok, totals}, fn encounter_id, {:ok, totals} ->
      case generate_for_encounter(encounter_id, opts) do
        {:ok, _result} ->
          {:cont, {:ok, %{totals | encounters: totals.encounters + 1}}}

        {:error, reason} ->
          {:halt, {:error, %{encounter_id: encounter_id, reason: reason, totals: totals}}}
      end
    end)
  end

  @doc """
  Reads the encounter document index from the configured store.
  """
  @spec list_index(keyword()) :: {:ok, map()} | {:error, term()}
  def list_index(opts \\ []) do
    opts
    |> Store.configured_module()
    |> fetch_index()
    |> case do
      {:ok, index} -> {:ok, normalize_document(index)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Reads one encounter document by source encounter key from the configured store.
  """
  @spec fetch_encounter(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def fetch_encounter(source_encounter_key, opts \\ []) when is_binary(source_encounter_key) do
    store = Store.configured_module(opts)

    case store.fetch(encounter_key(%{source_encounter_key: source_encounter_key})) do
      {:ok, body} ->
        with {:ok, document} <- Jason.decode(body) do
          {:ok, normalize_document(document)}
        end

      {:error, :enoent} ->
        {:error, :missing_document}

      {:error, {:http_error, 404, _body}} ->
        {:error, :missing_document}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def current_derivation_version, do: Derivation.current_version()

  defp encounter_ids(opts) do
    query =
      DimEncounter
      |> order_by([encounter], asc: encounter.id)
      |> select([encounter], encounter.id)

    case Keyword.fetch(opts, :encounter_id) do
      {:ok, encounter_id} -> [encounter_id]
      :error -> Repo.all(query)
    end
  end

  defp encounter_key(%{source_encounter_key: source_encounter_key}) do
    "encounters/#{source_encounter_key}.json"
  end

  defp put_json(store, key, payload) do
    with {:ok, body} <- Jason.encode(payload),
         :ok <- store.put(key, body) do
      {:ok, stored_path(store, key)}
    end
  end

  defp refresh_index(store, document) do
    with {:ok, current_index} <- fetch_index(store),
         index <- merge_index(current_index, document),
         {:ok, index_body} <- Jason.encode(index),
         :ok <- store.put("index.json", index_body) do
      {:ok, stored_path(store, "index.json")}
    end
  end

  defp fetch_index(store) do
    case store.fetch("index.json") do
      {:ok, body} -> Jason.decode(body)
      {:error, :enoent} -> {:ok, empty_index()}
      {:error, {:http_error, 404, _body}} -> {:ok, empty_index()}
      {:error, reason} -> {:error, reason}
    end
  end

  defp empty_index do
    %{"schema_version" => 1, "encounters" => []}
  end

  defp merge_index(index, document) do
    source_encounter_key = document.source_encounter_key

    encounters =
      index
      |> Map.get("encounters", [])
      |> Enum.reject(&(Map.get(&1, "source_encounter_key") == source_encounter_key))
      |> Kernel.++([index_entry(document)])
      |> Enum.sort_by(
        &{field(&1, :start_time) || "", field(&1, :source_encounter_key) || ""},
        :desc
      )

    %{
      schema_version: 1,
      generated_at: DateTime.utc_now(),
      encounters: encounters
    }
  end

  defp index_entry(document) do
    encounter = field!(document, :encounter)
    counts = field(document, :counts) || %{}

    failure_counts =
      case field(document, :failure_preview) do
        nil -> %{}
        failure_preview -> field(failure_preview, :counts) || %{}
      end

    pull_review = field(document, :pull_review) || %{}

    %{
      source_encounter_key: field!(document, :source_encounter_key),
      boss: field(encounter, :name),
      wow_encounter_id: field(encounter, :wow_encounter_id),
      difficulty_id: field(encounter, :difficulty_id),
      difficulty_name: field(encounter, :difficulty_name),
      instance_id: field(encounter, :instance_id),
      start_time: field(encounter, :start_time),
      end_time: field(encounter, :end_time),
      success: field(encounter, :success),
      fight_time_ms: field(encounter, :fight_time_ms),
      headline_counts: %{
        deaths: field(counts, :deaths) || 0,
        failures: field(failure_counts, :failures) || 0,
        failure_damage: field(failure_counts, :damage) || 0,
        players: field(counts, :players) || 0,
        low_damage: length(field(pull_review, :low_dps) || [])
      }
    }
  end

  defp field(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp field!(map, key) do
    field(map, key) || raise KeyError, key: key, term: map
  end

  defp stored_path(WeGoNext.Documents.Store.FileSystem, key),
    do: WeGoNext.Documents.Store.FileSystem.path_for_key(key)

  defp stored_path(_store, key), do: key

  defp normalize_document(value) when is_list(value), do: Enum.map(value, &normalize_document/1)

  defp normalize_document(value) when is_map(value) do
    Map.new(value, fn {key, value} -> {normalize_key(key), normalize_value(key, value)} end)
  end

  defp normalize_document(value), do: value

  defp normalize_value(key, value) when key in ["start_time", "end_time", "generated_at"] do
    parse_datetime(value)
  end

  defp normalize_value(_key, value), do: normalize_document(value)

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = value), do: value

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> value
    end
  end

  defp parse_datetime(value), do: value
end
