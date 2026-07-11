defmodule WeGoNext.Documents.Upload do
  @moduledoc """
  Publishes generated encounter documents to the public document store.
  """

  import Ecto.Query

  alias WeGoNext.Documents
  alias WeGoNext.Documents.Store
  alias WeGoNext.Mirror.MirrorUpload
  alias WeGoNext.Repo

  @spec publish(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def publish(source_encounter_key, opts \\ []) when is_binary(source_encounter_key) do
    source_store = Keyword.get(opts, :source_store) || Store.configured_module(opts)
    destination_store = Keyword.get(opts, :destination_store, WeGoNext.Documents.Store.R2)
    encounter_key = encounter_key(source_encounter_key)

    with {:ok, document_body} <- source_store.fetch(encounter_key),
         :ok <- destination_store.put(encounter_key, document_body),
         :ok <- refresh_public_index(source_store, destination_store, source_encounter_key) do
      {:ok,
       %{
         source_encounter_key: source_encounter_key,
         encounter_key: encounter_key,
         index_key: "index.json"
       }}
    end
  end

  defp refresh_public_index(source_store, destination_store, source_encounter_key) do
    :global.trans({{__MODULE__, :public_index}, self()}, fn ->
      with {:ok, index} <- public_index(source_store, destination_store, source_encounter_key),
           {:ok, index_body} <- Jason.encode(index) do
        destination_store.put("index.json", index_body)
      end
    end)
  end

  defp public_index(source_store, destination_store, current_source_encounter_key) do
    uploaded_keys = uploaded_source_keys(current_source_encounter_key)
    existing_index = existing_public_index(destination_store)
    existing_entries = Map.new(existing_index, &{field(&1, :source_encounter_key), &1})

    keys =
      [current_source_encounter_key | uploaded_keys ++ Map.keys(existing_entries)]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    with {:ok, encounters} <- public_index_entries(source_store, keys, existing_entries) do
      {:ok,
       %{
         schema_version: 1,
         generated_at: DateTime.utc_now(),
         encounters: encounters
       }}
    end
  end

  defp uploaded_source_keys(current_source_encounter_key) do
    published_keys =
      MirrorUpload
      |> where([upload], upload.state == "published")
      |> select([upload], upload.source_encounter_key)
      |> Repo.all()

    [current_source_encounter_key | published_keys]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp public_index_entries(source_store, source_encounter_keys, existing_entries) do
    source_encounter_keys
    |> Enum.reduce_while({:ok, []}, fn source_encounter_key, {:ok, entries} ->
      case fetch_index_entry(source_store, source_encounter_key, existing_entries) do
        {:ok, entry} -> {:cont, {:ok, [entry | entries]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entries} ->
        {:ok,
         Enum.sort_by(
           entries,
           &{field(&1, :start_time) || "", field(&1, :source_encounter_key) || ""},
           :desc
         )}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_index_entry(source_store, source_encounter_key, existing_entries) do
    case source_store.fetch(encounter_key(source_encounter_key)) do
      {:ok, document_body} ->
        with {:ok, document} <- Jason.decode(document_body) do
          {:ok, Documents.index_entry(document)}
        end

      {:error, :enoent} ->
        case Map.fetch(existing_entries, source_encounter_key) do
          {:ok, entry} -> {:ok, entry}
          :error -> {:error, {:missing_document, source_encounter_key}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp encounter_key(source_encounter_key), do: "encounters/#{source_encounter_key}.json"

  defp existing_public_index(destination_store) do
    case destination_store.fetch("index.json") do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, %{"encounters" => encounters}} when is_list(encounters) -> encounters
          _other -> []
        end

      {:error, _reason} ->
        []
    end
  end

  defp field(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
