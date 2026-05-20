defmodule WeGoNext.SourceData do
  @moduledoc """
  Source-data ingestion context for patch-aware mechanic reference data.

  This context stores provenance-rich source rows only. Code-defined raid
  mechanic catalogs decide which source rows become active rules.
  """

  import Ecto.Query

  alias WeGoNext.Repo

  alias WeGoNext.SourceData.{
    DbmMechanicCandidate,
    EncounterReference,
    EncounterSpellReference,
    ReferenceImporter,
    SourceImport,
    SpellReference,
    WowAnalyzerTimelineCandidate
  }

  alias WeGoNext.SourceData.DBM.Parser
  alias WeGoNext.SourceData.WowAnalyzer.Parser, as: WowAnalyzerParser

  @dbm_source_system "dbm_retail"
  @wowanalyzer_source_system "wowanalyzer_agpl"
  @wowanalyzer_repository_license "AGPL-3.0-or-later"
  @default_product "wow"
  @default_channel "retail"
  @default_locale "enUS"
  @default_wowanalyzer_repo_root "/home/rpmessner/dev/games/wow-addons/WoWAnalyzer"
  @default_wowanalyzer_raid_slug "vs_dr_mqd"
  @default_wowanalyzer_raid_name "VS / DR / MQD"
  @default_dbm_midnight_roots [
    "/mnt/e/World of Warcraft/_retail_/Interface/AddOns/DBM-Raids-Midnight",
    "/mnt/e/World of Warcraft/_retail_/Interface/AddOns/DBM-Party-Midnight",
    "/mnt/e/World of Warcraft/_retail_/Interface/AddOns/DBM-Midnight",
    "/mnt/e/World of Warcraft/_retail_/Interface/AddOns/DBM-Delves-Midnight"
  ]

  @doc """
  Returns the installed DBM Midnight addon roots used by the default bulk import.
  """
  def default_dbm_midnight_roots, do: @default_dbm_midnight_roots

  @doc """
  Imports one DBM Lua module into source-data tables.
  """
  def import_dbm_file(path, opts \\ []) when is_binary(path) do
    with {:ok, parsed_module} <- Parser.parse_file(path),
         {:ok, content_hash} <- file_sha256(path) do
      Repo.transaction(fn ->
        source_import_action = source_import_action(path, content_hash, opts)
        source_import = upsert_source_import!(path, content_hash, parsed_module, opts)
        candidates = replace_dbm_candidates!(source_import, parsed_module, path)
        source_row_count = length(candidates)

        %{
          source_import: source_import,
          source_import_action: source_import_action,
          candidates: candidates,
          inserted_candidate_count: inserted_count(source_import_action, source_row_count),
          updated_candidate_count: updated_count(source_import_action, source_row_count)
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

  @doc """
  Imports all configured DBM Midnight addon roots and returns an operator summary.

  This source-data import only records source imports and parsed DBM mechanic
  source rows. It does not define active rules or rebuild gold facts.
  """
  def import_dbm_midnight_sources(opts \\ []) do
    opts
    |> Keyword.get(:roots, @default_dbm_midnight_roots)
    |> import_dbm_directories(opts)
  end

  @doc """
  Imports DBM Lua modules under each root and returns an aggregate summary.
  """
  def import_dbm_directories(roots, opts \\ []) when is_list(roots) do
    roots = Enum.map(roots, &Path.expand/1)

    case Enum.reject(roots, &File.dir?/1) do
      [] ->
        roots
        |> Enum.reduce_while({:ok, empty_dbm_import_summary(roots)}, fn root, {:ok, summary} ->
          case import_dbm_directory(root, opts) do
            {:ok, imports} ->
              {:cont, {:ok, merge_dbm_import_summary(summary, root, imports)}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end)

      missing_roots ->
        {:error, {:missing_roots, missing_roots}}
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

  @doc """
  Returns the default local WowAnalyzer repository root.
  """
  def default_wowanalyzer_repo_root, do: @default_wowanalyzer_repo_root

  @doc """
  Returns the default WowAnalyzer Midnight raid timeline source directory.
  """
  def default_wowanalyzer_timeline_root do
    Path.join([
      @default_wowanalyzer_repo_root,
      "src/game/raids",
      @default_wowanalyzer_raid_slug
    ])
  end

  @doc """
  Imports one WowAnalyzer TypeScript boss timeline file.

  The import records encounter timeline spell evidence as source rows only. It
  does not define active rules or rebuild gold facts.
  """
  def import_wowanalyzer_file(path, opts \\ []) when is_binary(path) do
    with {:ok, parsed_file} <- WowAnalyzerParser.parse_file(path),
         {:ok, content_hash} <- file_sha256(path) do
      Repo.transaction(fn ->
        repository_revision = wowanalyzer_repository_revision(path, opts)

        repository_license =
          Keyword.get(opts, :repository_license, @wowanalyzer_repository_license)

        source_import_action = wowanalyzer_source_import_action(path, content_hash, opts)

        source_import =
          upsert_wowanalyzer_source_import!(
            path,
            content_hash,
            parsed_file,
            repository_revision,
            repository_license,
            opts
          )

        candidates =
          replace_wowanalyzer_timeline_candidates!(
            source_import,
            parsed_file,
            path,
            repository_revision,
            repository_license,
            opts
          )

        source_row_count = length(candidates)

        %{
          source_import: source_import,
          source_import_action: source_import_action,
          candidates: candidates,
          inserted_candidate_count: inserted_count(source_import_action, source_row_count),
          updated_candidate_count: updated_count(source_import_action, source_row_count)
        }
      end)
    end
  end

  @doc """
  Imports every WowAnalyzer TypeScript boss timeline file under `root_path`.
  """
  def import_wowanalyzer_directory(root_path, opts \\ []) when is_binary(root_path) do
    root_path
    |> Path.join("**/*.ts")
    |> Path.wildcard()
    |> Enum.reject(&(Path.basename(&1) == "index.ts"))
    |> Enum.sort()
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, imported} ->
      case import_wowanalyzer_file(path, opts) do
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

  @doc """
  Imports the configured WowAnalyzer timeline source directories.
  """
  def import_wowanalyzer_sources(opts \\ []) do
    opts
    |> wowanalyzer_roots()
    |> import_wowanalyzer_directories(opts)
  end

  def import_wowanalyzer_directories(roots, opts \\ []) when is_list(roots) do
    roots = Enum.map(roots, &Path.expand/1)

    case Enum.reject(roots, &File.dir?/1) do
      [] ->
        roots
        |> Enum.reduce_while({:ok, empty_wowanalyzer_import_summary(roots, opts)}, fn root,
                                                                                      {:ok,
                                                                                       summary} ->
          case import_wowanalyzer_directory(root, opts) do
            {:ok, imports} ->
              {:cont, {:ok, merge_wowanalyzer_import_summary(summary, root, imports)}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end)

      missing_roots ->
        {:error, {:missing_roots, missing_roots}}
    end
  end

  def list_wowanalyzer_timeline_candidates(opts \\ []) do
    query =
      WowAnalyzerTimelineCandidate
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
      case Keyword.get(opts, :timeline_type) do
        nil -> query
        timeline_type -> where(query, [c], c.timeline_type == ^timeline_type)
      end

    query =
      case Keyword.get(opts, :event_type) do
        nil -> query
        event_type -> where(query, [c], c.event_type == ^event_type)
      end

    query =
      case Keyword.get(opts, :inferred_mechanic_type) do
        nil -> query
        mechanic_type -> where(query, [c], c.inferred_mechanic_type == ^mechanic_type)
      end

    Repo.all(query)
  end

  defp source_import_action(path, content_hash, opts) do
    source_system = Keyword.get(opts, :source_system, @dbm_source_system)

    if source_import_exists?(source_system, path, content_hash) do
      :updated
    else
      :inserted
    end
  end

  defp source_import_exists?(source_system, path, content_hash) do
    SourceImport
    |> where(
      [source_import],
      source_import.source_system == ^source_system and source_import.source_path == ^path and
        source_import.content_hash == ^content_hash
    )
    |> Repo.exists?()
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
      product: source_import.product,
      channel: source_import.channel,
      build_version: source_import.build_version,
      build_key: source_import.build_key,
      inserted_at: now,
      updated_at: now
    }
  end

  defp inserted_count(:inserted, count), do: count
  defp inserted_count(:updated, _count), do: 0

  defp updated_count(:updated, count), do: count
  defp updated_count(:inserted, _count), do: 0

  defp empty_dbm_import_summary(roots) do
    %{
      roots: roots,
      files_imported: 0,
      source_imports_inserted: 0,
      source_imports_updated: 0,
      candidates_inserted: 0,
      candidates_updated: 0,
      imports: []
    }
  end

  defp merge_dbm_import_summary(summary, root, imports) do
    Enum.reduce(imports, %{summary | imports: summary.imports ++ [{root, imports}]}, fn import,
                                                                                        acc ->
      %{
        acc
        | files_imported: acc.files_imported + 1,
          source_imports_inserted:
            acc.source_imports_inserted + action_count(import.source_import_action, :inserted),
          source_imports_updated:
            acc.source_imports_updated + action_count(import.source_import_action, :updated),
          candidates_inserted: acc.candidates_inserted + import.inserted_candidate_count,
          candidates_updated: acc.candidates_updated + import.updated_candidate_count
      }
    end)
  end

  defp action_count(action, action), do: 1
  defp action_count(_actual, _expected), do: 0

  defp wowanalyzer_source_import_action(path, content_hash, opts) do
    source_system = Keyword.get(opts, :source_system, @wowanalyzer_source_system)

    if source_import_exists?(source_system, path, content_hash) do
      :updated
    else
      :inserted
    end
  end

  defp upsert_wowanalyzer_source_import!(
         path,
         content_hash,
         parsed_file,
         repository_revision,
         repository_license,
         opts
       ) do
    now = DateTime.utc_now()
    entries = parsed_file.timeline_entries

    attrs = %{
      source_system: Keyword.get(opts, :source_system, @wowanalyzer_source_system),
      source_path: path,
      product: Keyword.get(opts, :product, @default_product),
      channel: Keyword.get(opts, :channel, @default_channel),
      build_version: Keyword.get(opts, :build_version),
      build_key: Keyword.get(opts, :build_key),
      addon_revision: repository_revision,
      locale: Keyword.get(opts, :locale),
      content_hash: content_hash,
      imported_at: now,
      metadata: %{
        "source_format" => "wowanalyzer_raid_boss_timeline_ts",
        "repository_revision" => repository_revision,
        "repository_license" => repository_license,
        "raid_slug" => Keyword.get(opts, :raid_slug, @default_wowanalyzer_raid_slug),
        "raid_name" => Keyword.get(opts, :raid_name, @default_wowanalyzer_raid_name),
        "encounter_id" => parsed_file.encounter_id,
        "encounter_name" => parsed_file.encounter_name,
        "timeline_ability_count" => Enum.count(entries, &(&1.timeline_type == "ability")),
        "timeline_debuff_count" => Enum.count(entries, &(&1.timeline_type == "debuff")),
        "agpl_handling" =>
          "Imported as provenance-tracked source evidence; WowAnalyzer runtime code is not copied into the medallion fact path."
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

  defp replace_wowanalyzer_timeline_candidates!(
         %SourceImport{} = source_import,
         parsed_file,
         path,
         repository_revision,
         repository_license,
         opts
       ) do
    from(candidate in WowAnalyzerTimelineCandidate,
      where: candidate.source_import_id == ^source_import.id
    )
    |> Repo.delete_all()

    now = DateTime.utc_now()

    rows =
      parsed_file.timeline_entries
      |> Enum.reject(&is_nil(&1.spell_id))
      |> Enum.map(fn entry ->
        wowanalyzer_candidate_attrs(
          entry,
          parsed_file,
          source_import,
          path,
          repository_revision,
          repository_license,
          opts,
          now
        )
      end)

    if rows != [] do
      Repo.insert_all(WowAnalyzerTimelineCandidate, rows)
    end

    WowAnalyzerTimelineCandidate
    |> where([candidate], candidate.source_import_id == ^source_import.id)
    |> order_by([candidate], asc: candidate.source_line)
    |> Repo.all()
  end

  defp wowanalyzer_candidate_attrs(
         entry,
         parsed_file,
         source_import,
         path,
         repository_revision,
         repository_license,
         opts,
         now
       ) do
    %{
      source_import_id: source_import.id,
      raid_slug: Keyword.get(opts, :raid_slug, @default_wowanalyzer_raid_slug),
      raid_name: Keyword.get(opts, :raid_name, @default_wowanalyzer_raid_name),
      encounter_id: parsed_file.encounter_id,
      encounter_name: parsed_file.encounter_name,
      timeline_type: entry.timeline_type,
      event_type: entry.event_type,
      spell_id: entry.spell_id,
      boss_only: entry.boss_only,
      comment: entry.comment,
      inference_tags: entry.inference_tags,
      inferred_mechanic_type: entry.inferred_mechanic_type,
      confidence: entry.confidence,
      review_status: "inferred",
      repository_revision: repository_revision,
      repository_license: repository_license,
      source_file: path,
      source_line: entry.source_line,
      source_line_text: entry.source_line_text,
      raw_entry: entry.raw_entry,
      product: source_import.product,
      channel: source_import.channel,
      build_version: source_import.build_version,
      build_key: source_import.build_key,
      inserted_at: now,
      updated_at: now
    }
  end

  defp wowanalyzer_roots(opts) do
    cond do
      Keyword.has_key?(opts, :roots) ->
        Keyword.get(opts, :roots)

      Keyword.has_key?(opts, :root) ->
        [Keyword.fetch!(opts, :root)]

      true ->
        [default_wowanalyzer_timeline_root()]
    end
  end

  defp empty_wowanalyzer_import_summary(roots, opts) do
    %{
      roots: roots,
      files_imported: 0,
      source_imports_inserted: 0,
      source_imports_updated: 0,
      candidates_inserted: 0,
      candidates_updated: 0,
      repository_license: Keyword.get(opts, :repository_license, @wowanalyzer_repository_license),
      imports: []
    }
  end

  defp merge_wowanalyzer_import_summary(summary, root, imports) do
    Enum.reduce(imports, %{summary | imports: summary.imports ++ [{root, imports}]}, fn import,
                                                                                        acc ->
      %{
        acc
        | files_imported: acc.files_imported + 1,
          source_imports_inserted:
            acc.source_imports_inserted + action_count(import.source_import_action, :inserted),
          source_imports_updated:
            acc.source_imports_updated + action_count(import.source_import_action, :updated),
          candidates_inserted: acc.candidates_inserted + import.inserted_candidate_count,
          candidates_updated: acc.candidates_updated + import.updated_candidate_count
      }
    end)
  end

  defp wowanalyzer_repository_revision(path, opts) do
    Keyword.get(opts, :repository_revision) ||
      path
      |> wowanalyzer_repo_root(opts)
      |> git_revision()
  end

  defp wowanalyzer_repo_root(_path, opts) do
    Keyword.get(opts, :repo_root, @default_wowanalyzer_repo_root)
  end

  defp git_revision(nil), do: "unknown"

  defp git_revision(repo_root) do
    case System.cmd("git", ["-C", repo_root, "rev-parse", "HEAD"], stderr_to_stdout: true) do
      {revision, 0} -> String.trim(revision)
      _ -> "unknown"
    end
  rescue
    ErlangError -> "unknown"
  end

  @doc """
  Returns the default local spell-reference metadata path.
  """
  def default_spell_reference_path, do: ReferenceImporter.default_spell_reference_path()

  @doc """
  Imports one JSON file containing spell and/or encounter reference metadata.
  """
  def import_reference_metadata_file(path, opts \\ []) when is_binary(path) do
    ReferenceImporter.import_file(path, opts)
  end

  @doc """
  Imports multiple JSON files containing spell and/or encounter reference metadata.
  """
  def import_reference_metadata_files(paths, opts \\ []) when is_list(paths) do
    ReferenceImporter.import_files(paths, opts)
  end

  @doc """
  Imports the local `tools/spell_names.json` reference metadata export.
  """
  def import_default_spell_references(opts \\ []) do
    path = default_spell_reference_path()

    if File.regular?(path) do
      import_reference_metadata_file(path, opts)
    else
      {:error, {:missing_reference_file, path}}
    end
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
           :difficulty_id,
           :build_version,
           :source_priority,
           :metadata,
           :updated_at
         ]},
      conflict_target: [
        :encounter_id,
        :difficulty_id,
        :product,
        :channel,
        :build_key,
        :locale,
        :source_system
      ],
      returning: true
    )
  end

  @doc """
  Upserts one build-scoped encounter-to-spell reference row.
  """
  def upsert_encounter_spell_reference(attrs) when is_map(attrs) do
    %EncounterSpellReference{}
    |> EncounterSpellReference.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :source_import_id,
           :build_version,
           :source_priority,
           :metadata,
           :updated_at
         ]},
      conflict_target: [
        :encounter_id,
        :spell_id,
        :difficulty_id,
        :relationship_type,
        :product,
        :channel,
        :build_key,
        :locale,
        :source_system
      ],
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
      difficulty_id = normalize_optional_integer(reference_opt(opts, :difficulty_id))

      EncounterReference
      |> where([reference], reference.encounter_id == ^encounter_id)
      |> apply_reference_scope(opts)
      |> apply_difficulty_scope(difficulty_id)
      |> order_by([reference],
        asc:
          fragment("CASE WHEN ? = ? THEN 0 ELSE 1 END", reference.difficulty_id, ^difficulty_id),
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
  Lists build-scoped encounter-to-spell reference rows.
  """
  def list_encounter_spell_references(opts \\ []) do
    EncounterSpellReference
    |> apply_reference_scope(opts)
    |> maybe_where_integer(:encounter_id, opts)
    |> maybe_where_integer(:spell_id, opts)
    |> maybe_where_integer(:difficulty_id, opts)
    |> order_by([reference],
      asc: reference.source_priority,
      asc: reference.encounter_id,
      asc: reference.spell_id
    )
    |> Repo.all()
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

  defp apply_difficulty_scope(query, nil), do: query

  defp apply_difficulty_scope(query, difficulty_id) do
    where(query, [reference], reference.difficulty_id in ^[0, difficulty_id])
  end

  defp normalize_optional_integer(nil), do: nil

  defp normalize_optional_integer(value) do
    case normalize_integer(value) do
      {:ok, integer} -> integer
      :error -> nil
    end
  end

  defp maybe_where_integer(query, field_name, opts) do
    case reference_opt(opts, field_name) do
      nil ->
        query

      value ->
        with {:ok, integer} <- normalize_integer(value) do
          where(query, [reference], field(reference, ^field_name) == ^integer)
        else
          :error -> query
        end
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
