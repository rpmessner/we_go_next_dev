defmodule WeGoNext.SourceData do
  @moduledoc """
  Source-data ingestion context for patch-aware mechanic reference data.

  This context stores provenance-rich source rows only. Code-defined raid
  mechanic catalogs decide which source rows become active rules.
  """

  import Ecto.Query

  alias WeGoNext.Repo
  alias WeGoNext.Silver.{DamageDone, PlayerInfo}

  alias WeGoNext.SourceData.{
    DbmMechanicCandidate,
    EncounterReference,
    EncounterSpellReference,
    ReferenceImporter,
    SourceImport,
    SpellReference,
    WarcraftLogsApiFetch,
    WowAnalyzerTimelineCandidate
  }

  alias WeGoNext.SourceData.DBM.Parser
  alias WeGoNext.SourceData.WowAnalyzer.Parser, as: WowAnalyzerParser

  @dbm_source_system "dbm_retail"
  @wowanalyzer_source_system "wowanalyzer_agpl"
  @warcraft_logs_source_system "warcraft_logs_api"
  @wowanalyzer_repository_license "AGPL-3.0-or-later"
  @default_product "wow"
  @default_channel "retail"
  @default_locale "enUS"
  @default_warcraft_logs_api_version "v2"
  @default_warcraft_logs_api_endpoint "https://www.warcraftlogs.com/api/v2/client"
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

  @doc """
  Imports one saved Warcraft Logs API response payload as source-data evidence.

  The response is stored as raw external parser evidence for validation and
  investigation. It is intentionally separate from `combat_log_files` and does
  not sync active mechanics or rebuild gold facts.
  """
  def import_warcraft_logs_api_response(attrs) when is_map(attrs) or is_list(attrs) do
    with {:ok, fetch_attrs} <- warcraft_logs_fetch_attrs(attrs),
         {:ok, fetch_attrs} <- write_warcraft_logs_api_artifact(fetch_attrs) do
      Repo.transaction(fn ->
        source_import_action = warcraft_logs_source_import_action(fetch_attrs)
        source_import = upsert_warcraft_logs_source_import!(fetch_attrs)
        fetch = upsert_warcraft_logs_api_fetch!(source_import, fetch_attrs)

        %{
          source_import: source_import,
          source_import_action: source_import_action,
          fetch: fetch
        }
      end)
    end
  end

  @doc """
  Imports a JSON file containing one Warcraft Logs API response payload.
  """
  def import_warcraft_logs_api_response_file(path, attrs \\ []) when is_binary(path) do
    with {:ok, body} <- File.read(path),
         {:ok, payload} <- Jason.decode(body) do
      attrs
      |> put_data_attr(:response_payload, payload)
      |> put_data_attr(:response_body, body)
      |> import_warcraft_logs_api_response()
    end
  end

  def list_warcraft_logs_api_fetches(opts \\ []) do
    query =
      WarcraftLogsApiFetch
      |> order_by([fetch], desc: fetch.fetched_at, desc: fetch.id)

    query =
      case data_attr(opts, :report_code) do
        nil -> query
        report_code -> where(query, [fetch], fetch.report_code == ^report_code)
      end

    query =
      case data_attr(opts, :fight_id) do
        nil ->
          query

        fight_id ->
          case normalize_integer(fight_id) do
            {:ok, fight_id} -> where(query, [fetch], fetch.fight_id == ^fight_id)
            :error -> query
          end
      end

    query =
      case data_attr(opts, :query_name) do
        nil -> query
        query_name -> where(query, [fetch], fetch.query_name == ^query_name)
      end

    query =
      case data_attr(opts, :response_hash) do
        nil -> query
        response_hash -> where(query, [fetch], fetch.response_hash == ^response_hash)
      end

    Repo.all(query)
  end

  @doc """
  Compares local silver damage-done player totals against a Warcraft Logs API fetch.

  This is a validation aid only. It does not mutate silver, gold, rules, or
  imported Warcraft Logs evidence.
  """
  def compare_warcraft_logs_damage_done(encounter_dim_id, fetch_or_id, opts \\ []) do
    with {:ok, encounter_dim_id} <- normalize_integer(encounter_dim_id),
         %WarcraftLogsApiFetch{} = fetch <- get_warcraft_logs_api_fetch(fetch_or_id) do
      local_rows = local_damage_done_rows(encounter_dim_id)
      wcl_rows = warcraft_logs_damage_done_rows(fetch, opts)

      {:ok, damage_done_comparison(fetch, encounter_dim_id, local_rows, wcl_rows, opts)}
    else
      :error -> {:error, :invalid_encounter_dim_id}
      nil -> {:error, :warcraft_logs_fetch_not_found}
    end
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

  defp warcraft_logs_source_import_action(fetch_attrs) do
    if source_import_exists?(
         fetch_attrs.source_system,
         fetch_attrs.artifact_path,
         fetch_attrs.response_hash
       ) do
      :updated
    else
      :inserted
    end
  end

  defp upsert_warcraft_logs_source_import!(fetch_attrs) do
    attrs = %{
      source_system: fetch_attrs.source_system,
      source_path: fetch_attrs.artifact_path,
      product: fetch_attrs.product,
      channel: fetch_attrs.channel,
      build_version: fetch_attrs.build_version,
      build_key: fetch_attrs.build_key,
      locale: fetch_attrs.locale,
      content_hash: fetch_attrs.response_hash,
      imported_at: fetch_attrs.fetched_at,
      metadata: %{
        "source_format" => "warcraft_logs_api_response",
        "report_code" => fetch_attrs.report_code,
        "fight_id" => fetch_attrs.fight_id,
        "source_url" => fetch_attrs.source_url,
        "api_endpoint" => fetch_attrs.api_endpoint,
        "api_version" => fetch_attrs.api_version,
        "query_name" => fetch_attrs.query_name,
        "query_hash" => fetch_attrs.query_hash,
        "query_variables" => fetch_attrs.query_variables,
        "request_params" => fetch_attrs.request_params,
        "request_hash" => fetch_attrs.request_hash,
        "artifact_path" => fetch_attrs.artifact_path,
        "artifact_hash" => fetch_attrs.artifact_hash,
        "artifact_bytes" => fetch_attrs.artifact_bytes,
        "canonical_source_uri" => fetch_attrs.source_path,
        "fetch_metadata" => fetch_attrs.metadata,
        "annotation_only" =>
          "Warcraft Logs API data is external evidence only and does not create active rules or gold facts."
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
           :metadata,
           :imported_at,
           :updated_at
         ]},
      conflict_target: [:source_system, :source_path, :content_hash],
      returning: true
    )
  end

  defp upsert_warcraft_logs_api_fetch!(%SourceImport{} = source_import, fetch_attrs) do
    now = DateTime.utc_now()

    attrs = %{
      source_import_id: source_import.id,
      report_code: fetch_attrs.report_code,
      fight_id: fetch_attrs.fight_id,
      source_url: fetch_attrs.source_url,
      api_endpoint: fetch_attrs.api_endpoint,
      api_version: fetch_attrs.api_version,
      query_name: fetch_attrs.query_name,
      query_document: fetch_attrs.query_document,
      query_hash: fetch_attrs.query_hash,
      query_variables: fetch_attrs.query_variables,
      request_params: fetch_attrs.request_params,
      request_hash: fetch_attrs.request_hash,
      fetched_at: fetch_attrs.fetched_at,
      response_hash: fetch_attrs.response_hash,
      response_payload: fetch_attrs.response_payload,
      metadata: fetch_attrs.metadata,
      artifact_path: fetch_attrs.artifact_path,
      artifact_hash: fetch_attrs.artifact_hash,
      artifact_bytes: fetch_attrs.artifact_bytes,
      product: source_import.product,
      channel: source_import.channel,
      build_version: source_import.build_version,
      build_key: source_import.build_key,
      inserted_at: now,
      updated_at: now
    }

    %WarcraftLogsApiFetch{}
    |> WarcraftLogsApiFetch.changeset(attrs)
    |> Repo.insert!(
      on_conflict:
        {:replace,
         [
           :report_code,
           :fight_id,
           :source_url,
           :api_endpoint,
           :api_version,
           :query_name,
           :query_document,
           :query_hash,
           :query_variables,
           :request_params,
           :request_hash,
           :fetched_at,
           :response_hash,
           :response_payload,
           :metadata,
           :artifact_path,
           :artifact_hash,
           :artifact_bytes,
           :product,
           :channel,
           :build_version,
           :build_key,
           :updated_at
         ]},
      conflict_target: [:source_import_id],
      returning: true
    )
  end

  defp warcraft_logs_fetch_attrs(attrs) do
    with {:ok, report_code} <- required_text_attr(attrs, :report_code),
         {:ok, fight_id} <- required_integer_attr(attrs, :fight_id),
         {:ok, query_name} <- required_text_attr(attrs, :query_name),
         {:ok, response_payload} <- required_map_attr(attrs, :response_payload),
         {:ok, query_variables} <- optional_map_attr(attrs, :query_variables, %{}),
         {:ok, request_params} <- optional_map_attr(attrs, :request_params, %{}),
         {:ok, metadata} <- optional_map_attr(attrs, :metadata, %{}),
         {:ok, fetched_at} <- datetime_attr(data_attr(attrs, :fetched_at, DateTime.utc_now())) do
      query_document = optional_text_attr(attrs, :query_document)
      api_endpoint = optional_text_attr(attrs, :api_endpoint, @default_warcraft_logs_api_endpoint)
      api_version = optional_text_attr(attrs, :api_version, @default_warcraft_logs_api_version)

      response_hash =
        optional_text_attr(attrs, :response_hash) || response_hash(attrs, response_payload)

      query_hash = optional_text_attr(attrs, :query_hash) || sha256_hex(query_document || "")

      request_hash =
        optional_text_attr(attrs, :request_hash) ||
          json_sha256(%{
            api_endpoint: api_endpoint,
            api_version: api_version,
            query_document: query_document,
            query_name: query_name,
            query_variables: query_variables,
            request_params: request_params
          })

      source_url =
        optional_text_attr(attrs, :source_url) || warcraft_logs_report_url(report_code, fight_id)

      source_path =
        optional_text_attr(attrs, :source_path) ||
          warcraft_logs_source_path(report_code, fight_id, query_name, request_hash)

      {:ok,
       %{
         source_system: optional_text_attr(attrs, :source_system, @warcraft_logs_source_system),
         source_path: source_path,
         report_code: report_code,
         fight_id: fight_id,
         source_url: source_url,
         api_endpoint: api_endpoint,
         api_version: api_version,
         query_name: query_name,
         query_document: query_document,
         query_hash: query_hash,
         query_variables: query_variables,
         request_params: request_params,
         request_hash: request_hash,
         fetched_at: fetched_at,
         response_hash: response_hash,
         response_payload: response_payload,
         metadata: metadata,
         bronze_root:
           optional_text_attr(attrs, :bronze_root, default_warcraft_logs_bronze_root()),
         product: optional_text_attr(attrs, :product, @default_product),
         channel: optional_text_attr(attrs, :channel, @default_channel),
         build_version: optional_text_attr(attrs, :build_version),
         build_key: optional_text_attr(attrs, :build_key),
         locale: optional_text_attr(attrs, :locale)
       }}
    end
  end

  defp write_warcraft_logs_api_artifact(fetch_attrs) do
    artifact_path = warcraft_logs_artifact_path(fetch_attrs)

    artifact =
      %{
        "source_system" => fetch_attrs.source_system,
        "source_format" => "warcraft_logs_api_response",
        "report_code" => fetch_attrs.report_code,
        "fight_id" => fetch_attrs.fight_id,
        "source_url" => fetch_attrs.source_url,
        "api_endpoint" => fetch_attrs.api_endpoint,
        "api_version" => fetch_attrs.api_version,
        "query_name" => fetch_attrs.query_name,
        "query_document" => fetch_attrs.query_document,
        "query_hash" => fetch_attrs.query_hash,
        "query_variables" => fetch_attrs.query_variables,
        "request_params" => fetch_attrs.request_params,
        "request_hash" => fetch_attrs.request_hash,
        "fetched_at" => DateTime.to_iso8601(fetch_attrs.fetched_at),
        "response_hash" => fetch_attrs.response_hash,
        "metadata" => fetch_attrs.metadata,
        "response_payload" => fetch_attrs.response_payload
      }

    body = Jason.encode!(artifact, pretty: true)

    with :ok <- File.mkdir_p(Path.dirname(artifact_path)),
         :ok <- File.write(artifact_path, body) do
      {:ok,
       Map.merge(fetch_attrs, %{
         artifact_path: artifact_path,
         artifact_hash: sha256_hex(body),
         artifact_bytes: byte_size(body)
       })}
    end
  end

  defp warcraft_logs_artifact_path(fetch_attrs) do
    filename =
      [
        slug(fetch_attrs.query_name),
        String.slice(fetch_attrs.request_hash, 0, 12),
        String.slice(fetch_attrs.response_hash, 0, 12)
      ]
      |> Enum.join("-")
      |> Kernel.<>(".json")

    Path.join([
      fetch_attrs.bronze_root,
      "reports",
      fetch_attrs.report_code,
      "fights",
      Integer.to_string(fetch_attrs.fight_id),
      filename
    ])
  end

  defp default_warcraft_logs_bronze_root do
    Application.get_env(:we_go_next, :warcraft_logs_bronze_root) ||
      Path.expand("var/bronze/warcraft_logs", File.cwd!())
  end

  defp warcraft_logs_report_url(report_code, fight_id) do
    "https://www.warcraftlogs.com/reports/#{report_code}#fight=#{fight_id}"
  end

  defp warcraft_logs_source_path(report_code, fight_id, query_name, request_hash) do
    encoded_query_name = URI.encode_www_form(query_name)

    "warcraftlogs://reports/#{report_code}/fights/#{fight_id}/queries/#{encoded_query_name}/requests/#{request_hash}"
  end

  defp response_hash(attrs, response_payload) do
    case data_attr(attrs, :response_body) do
      body when is_binary(body) -> sha256_hex(body)
      _ -> json_sha256(response_payload)
    end
  end

  defp get_warcraft_logs_api_fetch(%WarcraftLogsApiFetch{} = fetch), do: fetch

  defp get_warcraft_logs_api_fetch(fetch_id) do
    case normalize_integer(fetch_id) do
      {:ok, fetch_id} -> Repo.get(WarcraftLogsApiFetch, fetch_id)
      :error -> nil
    end
  end

  defp local_damage_done_rows(encounter_dim_id) do
    DamageDone
    |> where([damage], damage.encounter_dim_id == ^encounter_dim_id)
    |> join(:left, [damage], player in PlayerInfo,
      on:
        player.encounter_dim_id == damage.encounter_dim_id and
          player.player_guid == damage.source_guid
    )
    |> group_by([damage, player], [damage.source_guid, player.player_name])
    |> select([damage, player], %{
      player_guid: damage.source_guid,
      player_name: player.player_name,
      total_damage: coalesce(sum(damage.total_amount), 0)
    })
    |> Repo.all()
    |> Enum.map(fn row ->
      %{
        player_guid: row.player_guid,
        player_name: row.player_name || row.player_guid,
        normalized_name: normalize_actor_name(row.player_name || row.player_guid),
        total_damage: integer_value(row.total_damage)
      }
    end)
  end

  defp warcraft_logs_damage_done_rows(%WarcraftLogsApiFetch{} = fetch, opts) do
    fetch.response_payload
    |> find_warcraft_logs_entries()
    |> Enum.reject(&(not Keyword.get(opts, :include_pets, false) and pet_entry?(&1)))
    |> Enum.flat_map(&warcraft_logs_damage_done_row/1)
    |> Enum.group_by(& &1.normalized_name)
    |> Enum.map(fn {_normalized_name, rows} ->
      first = List.first(rows)

      %{
        actor_id: first.actor_id,
        player_name: first.player_name,
        normalized_name: first.normalized_name,
        total_damage: rows |> Enum.map(& &1.total_damage) |> Enum.sum(),
        raw_entries: Enum.map(rows, & &1.raw_entry)
      }
    end)
  end

  defp find_warcraft_logs_entries(payload) do
    payload
    |> collect_entries_lists()
    |> Enum.find([], &damage_entry_list?/1)
  end

  defp collect_entries_lists(%{} = map) do
    direct =
      case map_value(map, :entries) do
        entries when is_list(entries) -> [entries]
        _ -> []
      end

    child_entries =
      map
      |> Map.values()
      |> Enum.flat_map(&collect_entries_lists/1)

    direct ++ child_entries
  end

  defp collect_entries_lists(list) when is_list(list),
    do: Enum.flat_map(list, &collect_entries_lists/1)

  defp collect_entries_lists(_value), do: []

  defp damage_entry_list?(entries) do
    Enum.any?(entries, fn entry ->
      is_map(entry) and not is_nil(entry_name(entry)) and not is_nil(entry_total(entry))
    end)
  end

  defp warcraft_logs_damage_done_row(entry) do
    with name when is_binary(name) <- entry_name(entry),
         total when is_integer(total) <- entry_total(entry) do
      [
        %{
          actor_id: map_value(entry, :id) || map_value(entry, :guid) || map_value(entry, :gameID),
          player_name: name,
          normalized_name: normalize_actor_name(name),
          total_damage: total,
          raw_entry: entry
        }
      ]
    else
      _ -> []
    end
  end

  defp entry_name(entry), do: optional_string(map_value(entry, :name))

  defp entry_total(entry) do
    entry
    |> map_first_value([:total, :totalDamage, :amount])
    |> normalize_optional_integer()
  end

  defp pet_entry?(entry) do
    not is_nil(map_value(entry, :petOwner)) or not is_nil(map_value(entry, :owner)) or
      map_value(entry, :type) in ["Pet", "Guardian"]
  end

  defp damage_done_comparison(fetch, encounter_dim_id, local_rows, wcl_rows, opts) do
    local_by_name = Map.new(local_rows, &{&1.normalized_name, &1})
    wcl_by_name = Map.new(wcl_rows, &{&1.normalized_name, &1})
    names = (Map.keys(local_by_name) ++ Map.keys(wcl_by_name)) |> Enum.uniq() |> Enum.sort()

    players =
      Enum.map(names, fn name ->
        local = Map.get(local_by_name, name)
        wcl = Map.get(wcl_by_name, name)
        local_total = (local && local.total_damage) || 0
        wcl_total = (wcl && wcl.total_damage) || 0
        delta = local_total - wcl_total
        delta_percent = percent_delta(delta, wcl_total)

        %{
          player_name: (local && local.player_name) || (wcl && wcl.player_name),
          normalized_name: name,
          local_player_guid: local && local.player_guid,
          local_total: local_total,
          warcraft_logs_total: wcl_total,
          delta: delta,
          delta_percent: delta_percent,
          status: comparison_status(local, wcl, delta, wcl_total, opts)
        }
      end)

    local_total = Enum.map(players, & &1.local_total) |> Enum.sum()
    wcl_total = Enum.map(players, & &1.warcraft_logs_total) |> Enum.sum()

    %{
      encounter_dim_id: encounter_dim_id,
      warcraft_logs_fetch_id: fetch.id,
      report_code: fetch.report_code,
      fight_id: fetch.fight_id,
      artifact_path: fetch.artifact_path,
      local_total: local_total,
      warcraft_logs_total: wcl_total,
      delta: local_total - wcl_total,
      delta_percent: percent_delta(local_total - wcl_total, wcl_total),
      players: players,
      matched_count: Enum.count(players, &(&1.status == :matched)),
      mismatched_count: Enum.count(players, &(&1.status == :mismatched)),
      local_only_count: Enum.count(players, &(&1.status == :local_only)),
      warcraft_logs_only_count: Enum.count(players, &(&1.status == :warcraft_logs_only))
    }
  end

  defp comparison_status(nil, _wcl, _delta, _wcl_total, _opts), do: :warcraft_logs_only
  defp comparison_status(_local, nil, _delta, _wcl_total, _opts), do: :local_only

  defp comparison_status(_local, _wcl, delta, wcl_total, opts) do
    tolerance_amount = Keyword.get(opts, :tolerance_amount, 1)
    tolerance_percent = Keyword.get(opts, :tolerance_percent, 0.005)
    tolerance = max(tolerance_amount, round(wcl_total * tolerance_percent))

    if abs(delta) <= tolerance, do: :matched, else: :mismatched
  end

  defp percent_delta(_delta, 0), do: nil
  defp percent_delta(delta, total), do: delta / total * 100.0

  defp normalize_actor_name(name) when is_binary(name) do
    name
    |> String.split("-", parts: 2)
    |> List.first()
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_actor_name(_name), do: ""

  defp map_first_value(map, keys) do
    Enum.find_value(keys, &map_value(map, &1))
  end

  defp map_value(%{} = map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_value(%{} = map, key), do: Map.get(map, key)
  defp map_value(_value, _key), do: nil

  defp optional_string(nil), do: nil
  defp optional_string(value), do: to_string(value)

  defp integer_value(%Decimal{} = value), do: Decimal.to_integer(value)
  defp integer_value(value) when is_integer(value), do: value
  defp integer_value(value) when is_float(value), do: round(value)
  defp integer_value(_value), do: 0

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
      {:ok, sha256_hex(body)}
    end
  end

  defp json_sha256(payload) do
    payload
    |> Jason.encode!()
    |> sha256_hex()
  end

  defp sha256_hex(body) when is_binary(body) do
    :sha256
    |> :crypto.hash(body)
    |> Base.encode16(case: :lower)
  end

  defp put_data_attr(attrs, key, value) when is_list(attrs), do: Keyword.put(attrs, key, value)
  defp put_data_attr(attrs, key, value) when is_map(attrs), do: Map.put(attrs, key, value)

  defp data_attr(attrs, key, default \\ nil)

  defp data_attr(attrs, key, default) when is_list(attrs), do: Keyword.get(attrs, key, default)

  defp data_attr(attrs, key, default) when is_map(attrs) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(attrs, key) -> Map.get(attrs, key)
      Map.has_key?(attrs, string_key) -> Map.get(attrs, string_key)
      true -> default
    end
  end

  defp required_text_attr(attrs, key) do
    case optional_text_attr(attrs, key) do
      nil -> {:error, {:missing_required, key}}
      value -> {:ok, value}
    end
  end

  defp optional_text_attr(attrs, key, default \\ nil) do
    case data_attr(attrs, key, default) do
      nil ->
        nil

      value ->
        value
        |> to_string()
        |> String.trim()
        |> case do
          "" -> nil
          text -> text
        end
    end
  end

  defp required_integer_attr(attrs, key) do
    case data_attr(attrs, key) do
      nil ->
        {:error, {:missing_required, key}}

      value ->
        case normalize_integer(value) do
          {:ok, integer} -> {:ok, integer}
          :error -> {:error, {:invalid_integer, key}}
        end
    end
  end

  defp required_map_attr(attrs, key) do
    case data_attr(attrs, key) do
      nil -> {:error, {:missing_required, key}}
      value -> json_map_attr(value, key)
    end
  end

  defp optional_map_attr(attrs, key, default) do
    case data_attr(attrs, key) do
      nil -> {:ok, default}
      value -> json_map_attr(value, key)
    end
  end

  defp json_map_attr(value, key) when is_map(value) do
    value
    |> Jason.encode!()
    |> Jason.decode()
    |> case do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:error, {:invalid_map, key}}
    end
  end

  defp json_map_attr(_value, key), do: {:error, {:invalid_map, key}}

  defp datetime_attr(value) do
    case Ecto.Type.cast(:utc_datetime_usec, value) do
      {:ok, datetime} -> {:ok, datetime}
      :error -> {:error, {:invalid_datetime, :fetched_at}}
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

  defp normalize_integer(value) when is_float(value), do: {:ok, round(value)}

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _ -> :error
    end
  end

  defp normalize_integer(_value), do: :error

  defp slug(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "query"
      slug -> slug
    end
  end
end
