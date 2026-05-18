defmodule WeGoNext.SourceData do
  @moduledoc """
  Source-data ingestion context for patch-aware mechanic inference.

  This context stores evidence and inferred candidates only. It does not mutate
  active rules or gold facts.
  """

  import Ecto.Query

  alias WeGoNext.Repo

  alias WeGoNext.SourceData.{
    DbmMechanicCandidate,
    EncounterReference,
    SourceImport,
    SpellReference
  }

  alias WeGoNext.SourceData.DBM.Parser

  @dbm_source_system "dbm_retail"
  @default_product "wow"
  @default_channel "retail"
  @default_locale "enUS"

  @doc """
  Imports one DBM Lua module into source-data tables.
  """
  def import_dbm_file(path, opts \\ []) when is_binary(path) do
    with {:ok, parsed_module} <- Parser.parse_file(path),
         {:ok, content_hash} <- file_sha256(path) do
      Repo.transaction(fn ->
        source_import = upsert_source_import!(path, content_hash, parsed_module, opts)
        candidates = replace_dbm_candidates!(source_import, parsed_module, path)

        %{
          source_import: source_import,
          candidates: candidates
        }
      end)
    end
  end

  @doc """
  Imports every DBM Lua module under `root_path` that declares special warnings.
  """
  def import_dbm_directory(root_path, opts \\ []) when is_binary(root_path) do
    root_path
    |> Path.join("**/*.lua")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, imported} ->
      case import_dbm_file(path, opts) do
        {:ok, %{candidates: []}} ->
          {:cont, {:ok, imported}}

        {:ok, result} ->
          {:cont, {:ok, [result | imported]}}

        {:error, reason} ->
          {:halt, {:error, {path, reason}}}
      end
    end)
    |> case do
      {:ok, imported} -> {:ok, Enum.reverse(imported)}
      {:error, reason} -> {:error, reason}
    end
  end

  def list_dbm_candidates(opts \\ []) do
    query =
      DbmMechanicCandidate
      |> order_by([c], asc: c.source_file, asc: c.source_line)

    query =
      case Keyword.get(opts, :encounter_id) do
        nil -> query
        encounter_id -> where(query, [c], c.encounter_id == ^encounter_id)
      end

    query =
      case Keyword.get(opts, :spell_id) do
        nil -> query
        spell_id -> where(query, [c], c.spell_id == ^spell_id)
      end

    query =
      case Keyword.get(opts, :inferred_mechanic_type) do
        nil -> query
        mechanic_type -> where(query, [c], c.inferred_mechanic_type == ^mechanic_type)
      end

    Repo.all(query)
  end

  defp upsert_source_import!(path, content_hash, parsed_module, opts) do
    now = DateTime.utc_now()

    attrs = %{
      source_system: Keyword.get(opts, :source_system, @dbm_source_system),
      source_path: path,
      product: Keyword.get(opts, :product, @default_product),
      channel: Keyword.get(opts, :channel, @default_channel),
      build_version: Keyword.get(opts, :build_version),
      build_key: Keyword.get(opts, :build_key),
      addon_revision: parsed_module.module_revision,
      locale: Keyword.get(opts, :locale),
      content_hash: content_hash,
      imported_at: now,
      metadata: %{
        "module_id" => parsed_module.module_id,
        "module_addon" => parsed_module.module_addon,
        "module_map_id" => parsed_module.module_map_id,
        "encounter_id" => parsed_module.encounter_id,
        "zone_id" => parsed_module.zone_id,
        "creature_ids" => parsed_module.creature_ids
      }
    }

    %SourceImport{}
    |> SourceImport.changeset(attrs)
    |> Repo.insert!(
      on_conflict:
        {:replace,
         [
           :product,
           :channel,
           :build_version,
           :build_key,
           :locale,
           :addon_revision,
           :metadata,
           :imported_at,
           :updated_at
         ]},
      conflict_target: [:source_system, :source_path, :content_hash],
      returning: true
    )
  end

  defp replace_dbm_candidates!(%SourceImport{} = source_import, parsed_module, path) do
    from(candidate in DbmMechanicCandidate,
      where: candidate.source_import_id == ^source_import.id
    )
    |> Repo.delete_all()

    now = DateTime.utc_now()

    rows =
      parsed_module.warnings
      |> Enum.reject(&is_nil(&1.spell_id))
      |> Enum.map(&candidate_attrs(&1, parsed_module, source_import, path, now))

    if rows != [] do
      Repo.insert_all(DbmMechanicCandidate, rows)
    end

    DbmMechanicCandidate
    |> where([candidate], candidate.source_import_id == ^source_import.id)
    |> order_by([candidate], asc: candidate.source_line)
    |> Repo.all()
  end

  defp candidate_attrs(warning, parsed_module, source_import, path, now) do
    %{
      source_import_id: source_import.id,
      module_addon: parsed_module.module_addon,
      module_id: parsed_module.module_id,
      module_map_id: parsed_module.module_map_id,
      module_revision: parsed_module.module_revision,
      encounter_id: parsed_module.encounter_id,
      zone_id: parsed_module.zone_id,
      creature_ids: parsed_module.creature_ids,
      warning_var: warning.warning_var,
      warning_constructor: warning.warning_constructor,
      spell_id: warning.spell_id,
      role_filter: warning.role_filter,
      label_tokens: warning.label_tokens,
      alert_tokens: warning.alert_tokens,
      inference_tags: warning.inference_tags,
      inferred_mechanic_type: warning.inferred_mechanic_type,
      confidence: warning.confidence,
      review_status: "inferred",
      source_file: path,
      source_line: warning.source_line,
      source_line_text: warning.source_line_text,
      raw_args: warning.raw_args,
      comment: warning.comment,
      inserted_at: now,
      updated_at: now
    }
  end

  @doc """
  Upserts one build-scoped spell reference row.
  """
  def upsert_spell_reference(attrs) when is_map(attrs) do
    %SpellReference{}
    |> SpellReference.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :source_import_id,
           :current_name,
           :localized_names,
           :build_version,
           :source_priority,
           :metadata,
           :updated_at
         ]},
      conflict_target: [:spell_id, :product, :channel, :build_key, :locale, :source_system],
      returning: true
    )
  end

  @doc """
  Upserts one build-scoped encounter reference row.
  """
  def upsert_encounter_reference(attrs) when is_map(attrs) do
    %EncounterReference{}
    |> EncounterReference.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :source_import_id,
           :current_name,
           :localized_names,
           :zone_id,
           :zone_name,
           :instance_id,
           :instance_name,
           :build_version,
           :source_priority,
           :metadata,
           :updated_at
         ]},
      conflict_target: [:encounter_id, :product, :channel, :build_key, :locale, :source_system],
      returning: true
    )
  end

  @doc """
  Returns the preferred spell reference for a spell id and build scope.

  The lookup prefers lower `source_priority` values, then newer rows. Callers
  should pass `:build_key` when resolving names for rules or facts.
  """
  def get_spell_reference(spell_id, opts \\ []) do
    with {:ok, spell_id} <- normalize_integer(spell_id) do
      SpellReference
      |> where([reference], reference.spell_id == ^spell_id)
      |> apply_reference_scope(opts)
      |> order_by([reference],
        asc: reference.source_priority,
        desc: reference.updated_at,
        desc: reference.id
      )
      |> limit(1)
      |> Repo.one()
    else
      :error -> nil
    end
  end

  @doc """
  Returns the preferred encounter reference for an encounter id and build scope.
  """
  def get_encounter_reference(encounter_id, opts \\ []) do
    with {:ok, encounter_id} <- normalize_integer(encounter_id) do
      EncounterReference
      |> where([reference], reference.encounter_id == ^encounter_id)
      |> apply_reference_scope(opts)
      |> order_by([reference],
        asc: reference.source_priority,
        desc: reference.updated_at,
        desc: reference.id
      )
      |> limit(1)
      |> Repo.one()
    else
      :error -> nil
    end
  end

  def resolve_spell_name(spell_id, opts \\ []) do
    case get_spell_reference(spell_id, opts) do
      %SpellReference{} = reference -> reference.current_name
      nil -> nil
    end
  end

  def resolve_encounter_name(encounter_id, opts \\ []) do
    case get_encounter_reference(encounter_id, opts) do
      %EncounterReference{} = reference -> reference.current_name
      nil -> nil
    end
  end

  defp file_sha256(path) do
    with {:ok, body} <- File.read(path) do
      hash =
        :sha256
        |> :crypto.hash(body)
        |> Base.encode16(case: :lower)

      {:ok, hash}
    end
  end

  defp apply_reference_scope(query, opts) do
    product = reference_opt(opts, :product, @default_product)
    channel = reference_opt(opts, :channel, @default_channel)
    locale = reference_opt(opts, :locale, @default_locale)
    build_key = reference_opt(opts, :build_key)

    query =
      query
      |> where([reference], reference.product == ^product)
      |> where([reference], reference.channel == ^channel)
      |> where([reference], reference.locale == ^locale)

    if is_nil(build_key) do
      query
    else
      where(query, [reference], reference.build_key == ^build_key)
    end
  end

  defp reference_opt(opts, key, default \\ nil)

  defp reference_opt(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)

  defp reference_opt(opts, key, default) when is_map(opts) do
    Map.get(opts, key, Map.get(opts, Atom.to_string(key), default))
  end

  defp normalize_integer(value) when is_integer(value), do: {:ok, value}

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _ -> :error
    end
  end

  defp normalize_integer(_value), do: :error
end
