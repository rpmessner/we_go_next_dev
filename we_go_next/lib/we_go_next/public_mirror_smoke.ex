defmodule WeGoNext.PublicMirrorSmoke do
  @moduledoc """
  Repeatable public mirror smoke over generated encounter documents.
  """

  import Ecto.Query

  alias WeGoNext.Documents
  alias WeGoNext.Documents.Store
  alias WeGoNext.Gold.DimEncounter
  alias WeGoNext.Mirror.{MirrorUpload, Outbox}
  alias WeGoNext.Repo

  @type result :: %{
          slug: String.t(),
          factful: map(),
          zero_failure: map(),
          drain: map(),
          uploaded_index: map(),
          public_probe: nil | map()
        }

  @doc """
  Rebuilds two encounter documents, uploads them through the outbox, and verifies
  the public document contract in the destination store.
  """
  @spec run(keyword()) :: {:ok, result()} | {:error, term()}
  def run(opts) when is_list(opts) do
    with {:ok, config} <- smoke_config(opts),
         {:ok, factful} <- encounter(config.factful_encounter_id),
         {:ok, zero_failure} <- encounter(config.zero_failure_encounter_id),
         {:ok, _totals} <- rebuild_documents(config, [factful.id, zero_failure.id]),
         {:ok, _uploads} <- enqueue_uploads([factful, zero_failure]),
         drain <- drain_outbox(config),
         :ok <- require_upload_success(drain),
         {:ok, uploaded_index} <- fetch_uploaded_index(config.destination_store),
         {:ok, factful_document} <- fetch_uploaded_document(config.destination_store, factful),
         {:ok, zero_failure_document} <-
           fetch_uploaded_document(config.destination_store, zero_failure),
         :ok <- verify_index(uploaded_index, [factful, zero_failure]),
         :ok <- verify_factful_document(factful_document),
         :ok <- verify_zero_failure_document(zero_failure_document),
         {:ok, public_probe} <-
           maybe_probe_public(
             config,
             factful,
             factful_document,
             zero_failure,
             zero_failure_document
           ) do
      {:ok,
       %{
         slug: config.slug,
         factful: summary(factful, factful_document),
         zero_failure: summary(zero_failure, zero_failure_document),
         drain: drain,
         uploaded_index: uploaded_index,
         public_probe: public_probe
       }}
    end
  end

  defp smoke_config(opts) do
    with {:ok, factful_encounter_id} <- fetch_positive_integer(opts, :factful_encounter_id),
         {:ok, zero_failure_encounter_id} <-
           fetch_positive_integer(opts, :zero_failure_encounter_id),
         {:ok, slug} <- fetch_slug(opts) do
      {:ok,
       %{
         factful_encounter_id: factful_encounter_id,
         zero_failure_encounter_id: zero_failure_encounter_id,
         slug: slug,
         source_store: Keyword.get(opts, :source_store) || Store.configured_module(),
         destination_store: Keyword.get(opts, :destination_store) || WeGoNext.Documents.Store.R2,
         limit: Keyword.get(opts, :limit, 20),
         max_concurrency: Keyword.get(opts, :max_concurrency, 2),
         public_base_url: trim_or_nil(Keyword.get(opts, :public_base_url))
       }}
    end
  end

  defp fetch_positive_integer(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_integer(value) and value > 0 -> {:ok, value}
      {:ok, value} -> {:error, {:invalid_positive_integer, key, value}}
      :error -> {:error, {:missing_required_option, key}}
    end
  end

  defp fetch_slug(opts) do
    slug = Keyword.get(opts, :slug, "raid-night")

    case trim_or_nil(slug) do
      nil -> {:error, {:missing_required_option, :slug}}
      slug -> {:ok, slug}
    end
  end

  defp encounter(encounter_id) do
    case Repo.get(DimEncounter, encounter_id) do
      %DimEncounter{source_encounter_key: key} = encounter when is_binary(key) ->
        {:ok, encounter}

      %DimEncounter{} ->
        {:error, {:missing_source_encounter_key, encounter_id}}

      nil ->
        {:error, {:encounter_not_found, encounter_id}}
    end
  end

  defp rebuild_documents(config, encounter_ids) do
    Documents.rebuild_encounters(encounter_ids, store: config.source_store)
  end

  defp enqueue_uploads(encounters) do
    uploads =
      Enum.map(encounters, fn encounter ->
        {:ok, upload} = Outbox.enqueue(encounter.source_encounter_key)
        upload
      end)

    {:ok, uploads}
  end

  defp drain_outbox(config) do
    Outbox.process_pending(
      limit: config.limit,
      max_concurrency: config.max_concurrency,
      source_store: config.source_store,
      destination_store: config.destination_store
    )
  end

  defp require_upload_success(%{error: 0}), do: :ok
  defp require_upload_success(drain), do: {:error, {:upload_failed, drain}}

  defp fetch_uploaded_index(destination_store) do
    with {:ok, body} <- destination_store.fetch("index.json"),
         {:ok, index} <- Jason.decode(body) do
      {:ok, index}
    end
  end

  defp fetch_uploaded_document(destination_store, encounter) do
    key = encounter_key(encounter.source_encounter_key)

    with {:ok, body} <- destination_store.fetch(key),
         {:ok, document} <- Jason.decode(body) do
      {:ok, document}
    end
  end

  defp verify_index(index, encounters) do
    uploaded_keys =
      index
      |> Map.get("encounters", [])
      |> Enum.map(&Map.get(&1, "source_encounter_key"))
      |> MapSet.new()

    missing =
      encounters
      |> Enum.map(& &1.source_encounter_key)
      |> Enum.reject(&MapSet.member?(uploaded_keys, &1))

    case missing do
      [] -> :ok
      missing -> {:error, {:missing_index_entries, missing}}
    end
  end

  defp verify_factful_document(document) do
    failures = get_in(document, ["failure_preview", "counts", "failures"]) || 0

    if failures > 0 do
      :ok
    else
      {:error, {:expected_factful_document, source_key(document), failures}}
    end
  end

  defp verify_zero_failure_document(document) do
    failures = get_in(document, ["failure_preview", "counts", "failures"]) || 0

    cond do
      failures != 0 ->
        {:error, {:expected_zero_failure_document, source_key(document), failures}}

      non_empty_detail?(document) ->
        :ok

      true ->
        {:error, {:expected_non_empty_detail, source_key(document)}}
    end
  end

  defp non_empty_detail?(document) do
    non_empty?(document["roster"]) or
      non_empty?(get_in(document, ["pull_review", "damage_done"])) or
      non_empty?(document["deaths"]) or
      non_empty?(get_in(document, ["interrupt_coverage", "spell_coverage"])) or
      non_empty?(get_in(document, ["pull_review", "damage_taken_spells"])) or
      non_empty?(get_in(document, ["pull_review", "debuffs", "boss"]))
  end

  defp non_empty?(value) when is_list(value), do: value != []
  defp non_empty?(_value), do: false

  defp maybe_probe_public(
         %{public_base_url: nil},
         _factful,
         _factful_document,
         _zero_failure,
         _zero_failure_document
       ),
       do: {:ok, nil}

  defp maybe_probe_public(config, factful, factful_document, zero_failure, zero_failure_document) do
    base = String.trim_trailing(config.public_base_url, "/")
    factful_name = get_in(factful_document, ["encounter", "name"]) || factful.name
    zero_failure_name = get_in(zero_failure_document, ["encounter", "name"]) || zero_failure.name
    factful_spell = factful_spell_name(factful_document)

    probes = [
      {:list, "#{base}/r/#{path_segment(config.slug)}", [factful_name, zero_failure_name], []},
      {:factful_detail,
       "#{base}/r/#{path_segment(config.slug)}/encounters/#{path_segment(factful.source_encounter_key)}?tab=failures",
       Enum.reject([factful_name, "Failures", factful_spell], &is_nil/1), []},
      {:zero_failure_detail,
       "#{base}/r/#{path_segment(config.slug)}/encounters/#{path_segment(zero_failure.source_encounter_key)}",
       [zero_failure_name, "Failures"], ["Empty Encounter Document", "Encounter Not Found"]}
    ]

    probes
    |> Enum.reduce_while({:ok, %{}}, fn {name, url, required, rejected}, {:ok, acc} ->
      case Req.get(url) do
        {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
          body = to_string(body)

          case verify_probe_body(body, required, rejected) do
            :ok ->
              {:cont,
               {:ok, Map.put(acc, name, %{url: url, status: status, bytes: byte_size(body)})}}

            {:error, reason} ->
              {:halt, {:error, {:public_probe_failed, name, url, reason}}}
          end

        {:ok, %Req.Response{status: status, body: body}} ->
          {:halt,
           {:error,
            {:public_probe_failed, name, url, status, String.slice(to_string(body), 0, 500)}}}

        {:error, reason} ->
          {:halt, {:error, {:public_probe_failed, name, url, reason}}}
      end
    end)
  end

  defp verify_probe_body(body, required, rejected) do
    missing = Enum.reject(required, &String.contains?(body, &1))
    present_rejected = Enum.filter(rejected, &String.contains?(body, &1))

    cond do
      missing != [] -> {:error, {:missing_expected_text, missing}}
      present_rejected != [] -> {:error, {:unexpected_text, present_rejected}}
      true -> :ok
    end
  end

  defp factful_spell_name(document) do
    document
    |> get_in(["failure_preview", "mechanics"])
    |> case do
      [%{"spell_name" => spell_name} | _rest] -> spell_name
      _other -> nil
    end
  end

  defp summary(encounter, document) do
    failures = get_in(document, ["failure_preview", "counts", "failures"]) || 0

    %{
      encounter_id: encounter.id,
      source_encounter_key: encounter.source_encounter_key,
      name: get_in(document, ["encounter", "name"]) || encounter.name,
      failures: failures,
      players: get_in(document, ["counts", "players"]) || 0,
      document_key: encounter_key(encounter.source_encounter_key),
      upload_state: upload_state(encounter.source_encounter_key)
    }
  end

  defp upload_state(source_encounter_key) do
    MirrorUpload
    |> where([upload], upload.source_encounter_key == ^source_encounter_key)
    |> select([upload], upload.state)
    |> Repo.one()
  end

  defp source_key(document), do: Map.get(document, "source_encounter_key")
  defp encounter_key(source_encounter_key), do: "encounters/#{source_encounter_key}.json"

  defp path_segment(value), do: URI.encode(value, &URI.char_unreserved?/1)

  defp trim_or_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp trim_or_nil(value), do: value
end
