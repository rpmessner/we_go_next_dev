defmodule WeGoNext.SourceData.ReferenceImporter do
  @moduledoc """
  Imports build-scoped spell and encounter metadata from local JSON exports.

  Supported inputs are intentionally narrow:

  * `%{"spell_id" => "Spell Name"}` maps, like `tools/spell_names.json`
  * bundles with `spells`, `encounters`, and optional `encounter_spells` arrays

  Imported rows remain source-data evidence. They do not activate rules or write
  gold facts.
  """

  import Ecto.Query

  alias WeGoNext.Repo
  alias WeGoNext.SourceData

  alias WeGoNext.SourceData.{
    EncounterReference,
    EncounterSpellReference,
    SourceImport,
    SpellReference
  }

  @default_product "wow"
  @default_channel "retail"
  @default_locale "enUS"
  @default_source_priority 50
  @id_name_map_source_system "local_spell_names_json"
  @reference_json_source_system "reference_metadata_json"

  @doc """
  Returns the local spell-name export path used when no explicit file is passed.
  """
  def default_spell_reference_path do
    Path.expand("../tools/spell_names.json", File.cwd!())
  end

  @doc """
  Imports one JSON reference metadata file.
  """
  def import_file(path, opts \\ []) when is_binary(path) do
    with {:ok, opts} <- normalize_opts(opts),
         {:ok, body} <- File.read(path),
         {:ok, payload} <- Jason.decode(body),
         {:ok, content_hash} <- sha256(body) do
      Repo.transaction(fn ->
        source_system = source_system(payload, opts)
        source_import_action = source_import_action(source_system, path, content_hash)
        source_import = upsert_source_import!(source_system, path, content_hash, payload, opts)

        spell_counts =
          payload
          |> spell_attrs(source_import, source_system, opts)
          |> import_rows(&spell_reference_exists?/1, &SourceData.upsert_spell_reference/1)

        encounter_counts =
          payload
          |> encounter_attrs(source_import, source_system, opts)
          |> import_rows(&encounter_reference_exists?/1, &SourceData.upsert_encounter_reference/1)

        encounter_spell_counts =
          payload
          |> encounter_spell_attrs(source_import, source_system, opts)
          |> import_rows(
            &encounter_spell_reference_exists?/1,
            &SourceData.upsert_encounter_spell_reference/1
          )

        %{
          source_import: source_import,
          source_import_action: source_import_action,
          spells_inserted: spell_counts.inserted,
          spells_updated: spell_counts.updated,
          encounters_inserted: encounter_counts.inserted,
          encounters_updated: encounter_counts.updated,
          encounter_spells_inserted: encounter_spell_counts.inserted,
          encounter_spells_updated: encounter_spell_counts.updated
        }
      end)
    end
  end

  @doc """
  Imports multiple reference metadata files and returns aggregate counts.
  """
  def import_files(paths, opts \\ []) when is_list(paths) do
    paths
    |> Enum.reduce_while({:ok, empty_summary(paths)}, fn path, {:ok, summary} ->
      case import_file(path, opts) do
        {:ok, import} ->
          {:cont, {:ok, merge_summary(summary, path, import)}}

        {:error, reason} ->
          {:halt, {:error, {path, reason}}}
      end
    end)
  end

  defp normalize_opts(opts) do
    if blank?(Keyword.get(opts, :build_key)) do
      {:error, :build_key_required}
    else
      {:ok, opts}
    end
  end

  defp source_system(payload, opts) do
    Keyword.get(opts, :source_system) ||
      if id_name_map?(payload),
        do: @id_name_map_source_system,
        else: @reference_json_source_system
  end

  defp source_import_action(source_system, path, content_hash) do
    if source_import_exists?(source_system, path, content_hash), do: :updated, else: :inserted
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

  defp upsert_source_import!(source_system, path, content_hash, payload, opts) do
    now = DateTime.utc_now()

    attrs = %{
      source_system: source_system,
      source_path: path,
      product: reference_opt(opts, :product, @default_product),
      channel: reference_opt(opts, :channel, @default_channel),
      build_version: reference_opt(opts, :build_version),
      build_key: reference_opt(opts, :build_key),
      locale: reference_opt(opts, :locale, @default_locale),
      content_hash: content_hash,
      imported_at: now,
      metadata: %{
        "source_format" => source_format(payload),
        "spell_count" => length(spell_entries(payload)),
        "encounter_count" => length(encounter_entries(payload)),
        "encounter_spell_count" => length(all_encounter_spell_entries(payload))
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

  defp spell_attrs(payload, source_import, source_system, opts) do
    Enum.map(spell_entries(payload), fn entry ->
      spell_id = integer!(field(entry, "spell_id") || field(entry, "id"), "spell_id")
      locale = reference_opt(opts, :locale, @default_locale)
      current_name = string!(preferred_name(entry, locale), "spell name")
      localized_names = localized_names(entry, locale, current_name)

      %{
        source_import_id: source_import.id,
        spell_id: spell_id,
        current_name: current_name,
        localized_names: localized_names,
        product: reference_opt(opts, :product, @default_product),
        channel: reference_opt(opts, :channel, @default_channel),
        build_version: reference_opt(opts, :build_version),
        build_key: reference_opt(opts, :build_key),
        locale: locale,
        source_system: source_system,
        source_priority: reference_opt(opts, :source_priority, @default_source_priority),
        metadata: reference_metadata(entry, spell_known_keys(), "spell")
      }
    end)
  end

  defp encounter_attrs(payload, source_import, source_system, opts) do
    Enum.map(encounter_entries(payload), fn entry ->
      encounter_id =
        integer!(field(entry, "encounter_id") || field(entry, "id"), "encounter_id")

      locale = reference_opt(opts, :locale, @default_locale)
      current_name = string!(preferred_name(entry, locale), "encounter name")
      localized_names = localized_names(entry, locale, current_name)

      %{
        source_import_id: source_import.id,
        encounter_id: encounter_id,
        current_name: current_name,
        localized_names: localized_names,
        zone_id: optional_integer(field(entry, "zone_id")),
        zone_name: field(entry, "zone_name"),
        instance_id: optional_integer(field(entry, "instance_id")),
        instance_name: field(entry, "instance_name"),
        difficulty_id: optional_integer(field(entry, "difficulty_id")) || 0,
        product: reference_opt(opts, :product, @default_product),
        channel: reference_opt(opts, :channel, @default_channel),
        build_version: reference_opt(opts, :build_version),
        build_key: reference_opt(opts, :build_key),
        locale: locale,
        source_system: source_system,
        source_priority: reference_opt(opts, :source_priority, @default_source_priority),
        metadata: reference_metadata(entry, encounter_known_keys(), "encounter")
      }
    end)
  end

  defp encounter_spell_attrs(payload, source_import, source_system, opts) do
    payload
    |> all_encounter_spell_entries()
    |> Enum.map(fn entry ->
      %{
        source_import_id: source_import.id,
        encounter_id:
          integer!(field(entry, "encounter_id") || field(entry, "id"), "encounter_id"),
        spell_id: integer!(field(entry, "spell_id"), "spell_id"),
        difficulty_id: optional_integer(field(entry, "difficulty_id")) || 0,
        relationship_type: field(entry, "relationship_type") || "mechanic",
        product: reference_opt(opts, :product, @default_product),
        channel: reference_opt(opts, :channel, @default_channel),
        build_version: reference_opt(opts, :build_version),
        build_key: reference_opt(opts, :build_key),
        locale: reference_opt(opts, :locale, @default_locale),
        source_system: source_system,
        source_priority: reference_opt(opts, :source_priority, @default_source_priority),
        metadata: reference_metadata(entry, encounter_spell_known_keys(), "encounter_spell")
      }
    end)
    |> Enum.uniq_by(fn attrs ->
      {
        attrs.encounter_id,
        attrs.spell_id,
        attrs.difficulty_id,
        attrs.relationship_type,
        attrs.product,
        attrs.channel,
        attrs.build_key,
        attrs.locale,
        attrs.source_system
      }
    end)
  end

  defp all_encounter_spell_entries(payload) do
    explicit_encounter_spell_entries(payload) ++
      Enum.flat_map(encounter_entries(payload), &encounter_spell_entries/1)
  end

  defp import_rows(attrs_list, exists?, upsert) do
    Enum.reduce(attrs_list, %{inserted: 0, updated: 0}, fn attrs, counts ->
      existed? = exists?.(attrs)

      case upsert.(attrs) do
        {:ok, _row} ->
          if existed? do
            %{counts | updated: counts.updated + 1}
          else
            %{counts | inserted: counts.inserted + 1}
          end

        {:error, changeset} ->
          Repo.rollback({:invalid_reference, changeset})
      end
    end)
  end

  defp spell_reference_exists?(attrs) do
    SpellReference
    |> where([reference], reference.spell_id == ^attrs.spell_id)
    |> where([reference], reference.product == ^attrs.product)
    |> where([reference], reference.channel == ^attrs.channel)
    |> where([reference], reference.build_key == ^attrs.build_key)
    |> where([reference], reference.locale == ^attrs.locale)
    |> where([reference], reference.source_system == ^attrs.source_system)
    |> Repo.exists?()
  end

  defp encounter_reference_exists?(attrs) do
    EncounterReference
    |> where([reference], reference.encounter_id == ^attrs.encounter_id)
    |> where([reference], reference.difficulty_id == ^attrs.difficulty_id)
    |> where([reference], reference.product == ^attrs.product)
    |> where([reference], reference.channel == ^attrs.channel)
    |> where([reference], reference.build_key == ^attrs.build_key)
    |> where([reference], reference.locale == ^attrs.locale)
    |> where([reference], reference.source_system == ^attrs.source_system)
    |> Repo.exists?()
  end

  defp encounter_spell_reference_exists?(attrs) do
    EncounterSpellReference
    |> where([reference], reference.encounter_id == ^attrs.encounter_id)
    |> where([reference], reference.spell_id == ^attrs.spell_id)
    |> where([reference], reference.difficulty_id == ^attrs.difficulty_id)
    |> where([reference], reference.relationship_type == ^attrs.relationship_type)
    |> where([reference], reference.product == ^attrs.product)
    |> where([reference], reference.channel == ^attrs.channel)
    |> where([reference], reference.build_key == ^attrs.build_key)
    |> where([reference], reference.locale == ^attrs.locale)
    |> where([reference], reference.source_system == ^attrs.source_system)
    |> Repo.exists?()
  end

  defp spell_entries(payload) when is_map(payload) do
    cond do
      id_name_map?(payload) ->
        entries_from_id_map(payload, "spell_id")

      is_map(payload["spells"]) ->
        entries_from_id_map(payload["spells"], "spell_id")

      is_list(payload["spells"]) ->
        payload["spells"]

      true ->
        []
    end
  end

  defp spell_entries(payload) when is_list(payload) do
    Enum.filter(payload, &(field(&1, "spell_id") || field(&1, "id")))
  end

  defp spell_entries(_payload), do: []

  defp encounter_entries(%{"encounters" => entries}) when is_list(entries), do: entries

  defp encounter_entries(entries) when is_list(entries),
    do: Enum.filter(entries, &field(&1, "encounter_id"))

  defp encounter_entries(_payload), do: []

  defp explicit_encounter_spell_entries(%{"encounter_spells" => entries}) when is_list(entries),
    do: entries

  defp explicit_encounter_spell_entries(%{"encounter_spells" => entries}) when is_map(entries) do
    entries_from_id_map(entries, "encounter_id")
  end

  defp explicit_encounter_spell_entries(_payload), do: []

  defp encounter_spell_entries(%{} = encounter_entry) do
    encounter_id = field(encounter_entry, "encounter_id") || field(encounter_entry, "id")
    difficulty_id = field(encounter_entry, "difficulty_id")

    encounter_entry
    |> field("spell_ids")
    |> case do
      spell_ids when is_list(spell_ids) ->
        Enum.map(spell_ids, fn spell_id ->
          %{
            "encounter_id" => encounter_id,
            "spell_id" => spell_id,
            "difficulty_id" => difficulty_id,
            "relationship_type" => "mechanic"
          }
        end)

      _ ->
        encounter_entry
        |> field("spells")
        |> spell_relationship_entries(encounter_id, difficulty_id)
    end
  end

  defp encounter_spell_entries(_payload), do: []

  defp spell_relationship_entries(spells, encounter_id, difficulty_id) when is_list(spells) do
    Enum.map(spells, fn
      %{} = spell ->
        Map.merge(spell, %{
          "encounter_id" => encounter_id,
          "difficulty_id" => field(spell, "difficulty_id") || difficulty_id,
          "relationship_type" => field(spell, "relationship_type") || "mechanic"
        })

      spell_id ->
        %{
          "encounter_id" => encounter_id,
          "spell_id" => spell_id,
          "difficulty_id" => difficulty_id,
          "relationship_type" => "mechanic"
        }
    end)
  end

  defp spell_relationship_entries(_spells, _encounter_id, _difficulty_id), do: []

  defp entries_from_id_map(map, id_key) do
    Enum.map(map, fn
      {id, name} when is_binary(name) ->
        %{id_key => id, "name" => name}

      {id, %{} = attrs} ->
        Map.put(attrs, id_key, Map.get(attrs, id_key, id))
    end)
  end

  defp id_name_map?(payload) when is_map(payload) and map_size(payload) > 0 do
    Enum.all?(payload, fn {key, value} ->
      match?({_, ""}, Integer.parse(to_string(key))) and (is_binary(value) or is_map(value))
    end)
  end

  defp id_name_map?(_payload), do: false

  defp preferred_name(entry, locale) do
    field(entry, "current_name") ||
      field(entry, "name") ||
      get_in(field(entry, "localized_names") || %{}, [locale])
  end

  defp localized_names(entry, locale, current_name) do
    case field(entry, "localized_names") do
      %{} = names when map_size(names) > 0 -> names
      _ -> %{locale => current_name}
    end
  end

  defp reference_metadata(entry, known_keys, source_type) do
    entry
    |> Map.drop(known_keys)
    |> Map.put("source_type", source_type)
  end

  defp source_format(payload) do
    cond do
      id_name_map?(payload) -> "id_name_map"
      is_map(payload) -> "reference_bundle"
      is_list(payload) -> "reference_list"
      true -> "unknown"
    end
  end

  defp empty_summary(paths) do
    %{
      files: paths,
      files_imported: 0,
      source_imports_inserted: 0,
      source_imports_updated: 0,
      spells_inserted: 0,
      spells_updated: 0,
      encounters_inserted: 0,
      encounters_updated: 0,
      encounter_spells_inserted: 0,
      encounter_spells_updated: 0,
      imports: []
    }
  end

  defp merge_summary(summary, path, import) do
    %{
      summary
      | files_imported: summary.files_imported + 1,
        source_imports_inserted:
          summary.source_imports_inserted + action_count(import.source_import_action, :inserted),
        source_imports_updated:
          summary.source_imports_updated + action_count(import.source_import_action, :updated),
        spells_inserted: summary.spells_inserted + import.spells_inserted,
        spells_updated: summary.spells_updated + import.spells_updated,
        encounters_inserted: summary.encounters_inserted + import.encounters_inserted,
        encounters_updated: summary.encounters_updated + import.encounters_updated,
        encounter_spells_inserted:
          summary.encounter_spells_inserted + import.encounter_spells_inserted,
        encounter_spells_updated:
          summary.encounter_spells_updated + import.encounter_spells_updated,
        imports: summary.imports ++ [{path, import}]
    }
  end

  defp action_count(action, action), do: 1
  defp action_count(_actual, _expected), do: 0

  defp sha256(body) do
    hash =
      :sha256
      |> :crypto.hash(body)
      |> Base.encode16(case: :lower)

    {:ok, hash}
  end

  defp optional_integer(nil), do: nil
  defp optional_integer(""), do: nil

  defp optional_integer(value) do
    case normalize_integer(value) do
      {:ok, integer} -> integer
      :error -> nil
    end
  end

  defp integer!(value, field_name) do
    case normalize_integer(value) do
      {:ok, integer} -> integer
      :error -> raise ArgumentError, "invalid #{field_name}: #{inspect(value)}"
    end
  end

  defp normalize_integer(value) when is_integer(value), do: {:ok, value}

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _ -> :error
    end
  end

  defp normalize_integer(_value), do: :error

  defp string!(value, _field_name) when is_binary(value) and value != "", do: value

  defp string!(value, field_name),
    do: raise(ArgumentError, "invalid #{field_name}: #{inspect(value)}")

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp reference_opt(opts, key, default \\ nil), do: Keyword.get(opts, key, default)

  defp field(%{} = map, key), do: Map.get(map, key)
  defp field(_value, _key), do: nil

  defp spell_known_keys do
    ~w(spell_id id current_name name localized_names)
  end

  defp encounter_known_keys do
    ~w(encounter_id id current_name name localized_names zone_id zone_name instance_id instance_name difficulty_id spell_ids spells)
  end

  defp encounter_spell_known_keys do
    ~w(encounter_id id spell_id difficulty_id relationship_type)
  end
end
