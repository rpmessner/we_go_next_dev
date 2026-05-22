defmodule WeGoNext.Rules do
  @moduledoc """
  Context for code-defined mechanic definitions.

  The public application model is intentionally simple: current-tier raid
  mechanics are defined in code, synced into the database, then used by failure
  rebuilds. Ruleset and criterion snapshot tables remain compatibility plumbing
  for fact keys and should not be exposed as product concepts.
  """

  import Ecto.Query

  alias WeGoNext.GameData.Raids
  alias WeGoNext.Gold.{DimMechanicCriterion, Rebuilds}
  alias WeGoNext.Repo
  alias WeGoNext.Rules.{MechanicCriterion, Ruleset}
  alias WeGoNext.SourceData

  @initial_rules_path Application.compile_env(
                        :we_go_next,
                        :initial_rules_path,
                        "priv/rules/initial_mechanic_rules.json"
                      )

  @doc """
  Lists rulesets in newest-first order.
  """
  def list_rulesets do
    Ruleset
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  def get_ruleset(id), do: Repo.get(Ruleset, id)
  def get_ruleset!(id), do: Repo.get!(Ruleset, id)

  def get_active_ruleset do
    Repo.get_by(Ruleset, status: "active")
  end

  @doc """
  Returns operator-facing status for code-defined current-tier mechanics.
  """
  def current_tier_mechanics_status do
    active_ruleset = get_active_ruleset()
    synced_mechanics_count = count_active_authored_rules(active_ruleset)
    failure_ready_mechanics_count = count_active_promoted_snapshots(active_ruleset)

    %{
      mechanics_synced?: not is_nil(active_ruleset),
      synced_mechanics_count: synced_mechanics_count,
      failure_ready_mechanics_count: failure_ready_mechanics_count,
      active_ruleset: active_ruleset,
      rulesets: list_rulesets(),
      authored_rules_count: Repo.aggregate(MechanicCriterion, :count),
      promoted_snapshots_count: Repo.aggregate(DimMechanicCriterion, :count),
      active_authored_rules_count: synced_mechanics_count,
      active_promoted_snapshots_count: failure_ready_mechanics_count
    }
  end

  @doc """
  Backward-compatible name for internal callers that still refer to operations.
  """
  def operations_status, do: current_tier_mechanics_status()

  def create_ruleset(attrs \\ %{}) do
    %Ruleset{}
    |> Ruleset.changeset(attrs)
    |> Repo.insert()
  end

  def update_ruleset(%Ruleset{} = ruleset, attrs) do
    ruleset
    |> Ruleset.changeset(attrs)
    |> Repo.update()
  end

  def change_ruleset(%Ruleset{} = ruleset, attrs \\ %{}) do
    Ruleset.changeset(ruleset, attrs)
  end

  @doc """
  Activates a ruleset and archives any previously active ruleset.
  """
  def activate_ruleset(%Ruleset{} = ruleset) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      from(r in Ruleset, where: r.status == "active" and r.id != ^ruleset.id)
      |> Repo.update_all(set: [status: "archived", archived_at: now, updated_at: now])

      ruleset
      |> Ruleset.changeset(%{status: "active", activated_at: now, archived_at: nil})
      |> Repo.update()
      |> case do
        {:ok, ruleset} -> ruleset
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def archive_ruleset(%Ruleset{} = ruleset) do
    now = DateTime.utc_now()

    ruleset
    |> Ruleset.changeset(%{status: "archived", archived_at: now})
    |> Repo.update()
  end

  def list_mechanic_criteria(%Ruleset{} = ruleset) do
    list_mechanic_criteria(ruleset.id)
  end

  def list_mechanic_criteria(ruleset_id) do
    MechanicCriterion
    |> where([c], c.ruleset_id == ^ruleset_id)
    |> order_by([c], asc: c.boss_name, asc: c.spell_name, asc: c.difficulty_id)
    |> Repo.all()
  end

  def get_mechanic_criterion(id), do: Repo.get(MechanicCriterion, id)
  def get_mechanic_criterion!(id), do: Repo.get!(MechanicCriterion, id)

  def create_mechanic_criterion(attrs \\ %{}) do
    %MechanicCriterion{}
    |> MechanicCriterion.changeset(attrs)
    |> Repo.insert()
  end

  def update_mechanic_criterion(%MechanicCriterion{} = mechanic_criterion, attrs) do
    mechanic_criterion
    |> MechanicCriterion.changeset(attrs)
    |> Repo.update()
  end

  def delete_mechanic_criterion(%MechanicCriterion{} = mechanic_criterion) do
    Repo.delete(mechanic_criterion)
  end

  def change_mechanic_criterion(%MechanicCriterion{} = mechanic_criterion, attrs \\ %{}) do
    MechanicCriterion.changeset(mechanic_criterion, attrs)
  end

  @doc """
  Promotes a ruleset's authored mechanic criteria into gold criterion snapshots.

  Promotion is idempotent by `source_rule_id`: running it again updates the
  existing gold snapshot for each rule rather than creating duplicates.
  """
  def promote_ruleset_to_gold(%Ruleset{} = ruleset), do: promote_ruleset_to_gold(ruleset, [])

  def promote_ruleset_to_gold(ruleset_id) when is_integer(ruleset_id) do
    ruleset_id
    |> get_ruleset!()
    |> promote_ruleset_to_gold()
  end

  def promote_ruleset_to_gold(%Ruleset{} = ruleset, opts) do
    Repo.transaction(fn ->
      ruleset = Repo.preload(ruleset, :mechanic_criteria)

      promoted =
        ruleset.mechanic_criteria
        |> Enum.sort_by(& &1.id)
        |> Enum.reduce_while([], fn criterion, promoted ->
          case upsert_gold_mechanic_criterion(ruleset, criterion, opts) do
            {:ok, snapshot} -> {:cont, [snapshot | promoted]}
            {:error, changeset} -> {:halt, Repo.rollback(changeset)}
          end
        end)
        |> Enum.reverse()

      %{ruleset: ruleset, criteria: promoted}
    end)
  end

  def promote_ruleset_to_gold(ruleset_id, opts) when is_integer(ruleset_id) do
    ruleset_id
    |> get_ruleset!()
    |> promote_ruleset_to_gold(opts)
  end

  @doc """
  Promotes the globally active ruleset into gold criterion snapshots.
  """
  def promote_active_ruleset_to_gold do
    case get_active_ruleset() do
      %Ruleset{} = ruleset -> promote_ruleset_to_gold(ruleset)
      nil -> {:error, :active_ruleset_not_found}
    end
  end

  @doc """
  Syncs the default current-tier raid catalogs into mechanic definitions.
  """
  def sync_current_tier_mechanics(opts \\ []) do
    sync_raid_mechanics("midnight_season_1", opts)
  end

  def sync_current_tier_rules(opts \\ []), do: sync_current_tier_mechanics(opts)

  @doc """
  Syncs code-defined raid mechanics into database-backed mechanic definitions.

  The raid catalog remains the curated source in code. This function mirrors its
  syncable mechanics into compatibility tables used by failure rebuilds.

  Supported options:

    * `:name` - internal definition set name, defaults to `"<raid name> Mechanics"`
    * `:version` - internal definition set version, defaults to `1`
    * `:status` - internal definition set status, defaults to `"draft"`
    * `:activate` - make synced definitions current, defaults to `false`
    * `:promote` - refresh fact-key criteria, defaults to `false`
    * `:rebuild` - make current, refresh fact keys, and rebuild failures, defaults to `false`
  """
  def sync_raid_mechanics(raid, opts \\ []) do
    opts = normalize_raid_sync_opts(opts)

    with {:ok, raid_module} <- raid_module(raid),
         {:ok, synced} <- seed_rules(raid_seed_payload(raid_module, opts), opts),
         {:ok, ruleset} <- maybe_activate_synced_ruleset(synced.ruleset, opts),
         {:ok, promoted} <- maybe_promote_synced_ruleset(ruleset, opts),
         {:ok, rebuild} <- maybe_rebuild_after_sync(opts) do
      {:ok, %{ruleset: ruleset, criteria: synced.criteria, promoted: promoted, rebuild: rebuild}}
    end
  end

  defp normalize_raid_sync_opts(opts) do
    if Keyword.get(opts, :rebuild, false) do
      opts
      |> Keyword.put(:activate, true)
      |> Keyword.put(:promote, true)
    else
      opts
    end
  end

  @doc """
  Seeds the legacy bundled initial mechanic rules JSON.

  This path is retained for historical fixtures and targeted tests. The normal
  operator bootstrap path is `sync_current_tier_rules/1`.
  """
  def seed_initial_rules(opts \\ []) do
    path = Keyword.get(opts, :path, @initial_rules_path)
    seed_rules_from_file(path)
  end

  @doc """
  Seeds authored rules from a JSON file.

  Expected shape:

      {
        "ruleset": {"name": "Initial Mechanic Rules", "version": 1},
        "criteria": []
      }

  Existing criteria with the same ruleset, spell, boss, and difficulty scope are
  updated through the normal changeset. New criteria are inserted through the
  same path.
  """
  def seed_rules_from_file(path, opts \\ []) when is_binary(path) do
    with {:ok, body} <- File.read(path),
         {:ok, payload} <- Jason.decode(body) do
      seed_rules(payload, opts)
    end
  end

  def seed_rules(%{} = payload, opts \\ []) do
    Repo.transaction(fn ->
      ruleset_attrs = map_get(payload, "ruleset", %{})
      criteria = map_get(payload, "criteria", [])

      with {:ok, ruleset} <- get_or_create_seed_ruleset(ruleset_attrs),
           {:ok, seeded_criteria} <- seed_mechanic_criteria(ruleset, criteria, opts) do
        %{ruleset: ruleset, criteria: seeded_criteria}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp get_or_create_seed_ruleset(attrs) when is_map(attrs) do
    name = map_get(attrs, "name")
    version = map_get(attrs, "version", 1)

    case Repo.get_by(Ruleset, name: name, version: version) do
      %Ruleset{} = ruleset ->
        update_ruleset(ruleset, ruleset_seed_attrs(attrs))

      nil ->
        create_ruleset(ruleset_seed_attrs(attrs))
    end
  end

  defp raid_module(module) when is_atom(module) do
    if function_exported?(module, :rule_criteria, 0) and function_exported?(module, :info, 0) do
      {:ok, module}
    else
      {:error, :invalid_raid_catalog}
    end
  end

  defp raid_module(slug) when is_binary(slug) do
    case Raids.by_slug(slug) do
      nil -> {:error, :raid_catalog_not_found}
      module -> {:ok, module}
    end
  end

  defp raid_seed_payload(raid_module, opts) do
    info = raid_module.info()

    %{
      "ruleset" => %{
        "name" => Keyword.get(opts, :name, "#{info.name} Mechanics"),
        "version" => Keyword.get(opts, :version, 1),
        "status" => Keyword.get(opts, :status, "draft")
      },
      "criteria" => raid_module.rule_criteria()
    }
  end

  defp maybe_activate_synced_ruleset(ruleset, opts) do
    if Keyword.get(opts, :activate, false) do
      activate_ruleset(ruleset)
    else
      {:ok, ruleset}
    end
  end

  defp maybe_promote_synced_ruleset(ruleset, opts) do
    if Keyword.get(opts, :promote, false) do
      promote_ruleset_to_gold(ruleset)
    else
      {:ok, nil}
    end
  end

  defp maybe_rebuild_after_sync(opts) do
    if Keyword.get(opts, :rebuild, false) do
      Rebuilds.rebuild_all(ruleset: :active)
    else
      {:ok, nil}
    end
  end

  defp ruleset_seed_attrs(attrs) do
    %{
      name: map_get(attrs, "name"),
      version: map_get(attrs, "version", 1),
      status: map_get(attrs, "status", "draft")
    }
  end

  defp seed_mechanic_criteria(%Ruleset{} = ruleset, criteria, opts) when is_list(criteria) do
    criteria
    |> Enum.reduce_while({:ok, []}, fn attrs, {:ok, seeded} ->
      case upsert_seed_mechanic_criterion(ruleset, attrs, opts) do
        {:ok, criterion} -> {:cont, {:ok, [criterion | seeded]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, seeded} -> {:ok, Enum.reverse(seeded)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp seed_mechanic_criteria(_ruleset, _criteria, _opts), do: {:error, :invalid_criteria}

  defp upsert_seed_mechanic_criterion(%Ruleset{} = ruleset, attrs, opts) when is_map(attrs) do
    attrs = Map.put(attrs, "ruleset_id", ruleset.id)
    attrs = apply_reference_names(attrs, opts)

    case get_seed_mechanic_criterion(ruleset.id, attrs) do
      %MechanicCriterion{} = criterion -> update_mechanic_criterion(criterion, attrs)
      nil -> create_mechanic_criterion(attrs)
    end
  end

  defp upsert_seed_mechanic_criterion(_ruleset, _attrs, _opts), do: {:error, :invalid_criterion}

  defp upsert_gold_mechanic_criterion(
         %Ruleset{} = ruleset,
         %MechanicCriterion{} = criterion,
         opts
       ) do
    attrs = gold_snapshot_attrs(ruleset, criterion, opts)

    %DimMechanicCriterion{}
    |> DimMechanicCriterion.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :ruleset_id,
           :ruleset_version,
           :product,
           :channel,
           :build_version,
           :build_key,
           :spell_id,
           :spell_name,
           :mechanic_type,
           :boss_encounter_id,
           :boss_name,
           :difficulty_id,
           :threshold,
           :notes,
           :active,
           :updated_at
         ]},
      conflict_target: [:source_rule_id],
      returning: true
    )
  end

  defp gold_snapshot_attrs(%Ruleset{} = ruleset, %MechanicCriterion{} = criterion, opts) do
    %{
      source_rule_id: criterion.id,
      ruleset_id: ruleset.id,
      ruleset_version: ruleset.version,
      product: ruleset_scope_value(ruleset, opts, :product),
      channel: ruleset_scope_value(ruleset, opts, :channel),
      build_version: ruleset_scope_value(ruleset, opts, :build_version),
      build_key: ruleset_scope_value(ruleset, opts, :build_key),
      spell_id: criterion.spell_id,
      spell_name: SourceData.resolve_spell_name(criterion.spell_id, opts) || criterion.spell_name,
      mechanic_type: criterion.mechanic_type,
      boss_encounter_id: criterion.boss_encounter_id,
      boss_name:
        SourceData.resolve_encounter_name(criterion.boss_encounter_id, opts) ||
          criterion.boss_name,
      difficulty_id: criterion.difficulty_id,
      threshold: criterion.threshold,
      notes: criterion.notes,
      active: criterion.active
    }
  end

  defp ruleset_scope_value(%Ruleset{} = ruleset, opts, key) do
    Keyword.get(opts, key, Map.fetch!(ruleset, key))
  end

  defp count_active_authored_rules(nil), do: 0

  defp count_active_authored_rules(%Ruleset{id: ruleset_id}) do
    MechanicCriterion
    |> where([c], c.ruleset_id == ^ruleset_id)
    |> Repo.aggregate(:count)
  end

  defp count_active_promoted_snapshots(nil), do: 0

  defp count_active_promoted_snapshots(%Ruleset{id: ruleset_id, version: version}) do
    DimMechanicCriterion
    |> where([c], c.ruleset_id == ^ruleset_id and c.ruleset_version == ^version)
    |> Repo.aggregate(:count)
  end

  defp apply_reference_names(attrs, opts) do
    attrs
    |> put_if_present(
      "spell_name",
      SourceData.resolve_spell_name(map_get(attrs, "spell_id"), opts)
    )
    |> put_if_present(
      "boss_name",
      SourceData.resolve_encounter_name(map_get(attrs, "boss_encounter_id"), opts)
    )
  end

  defp put_if_present(attrs, _key, nil), do: attrs
  defp put_if_present(attrs, key, value), do: Map.put(attrs, key, value)

  defp get_seed_mechanic_criterion(ruleset_id, attrs) do
    spell_id = map_get(attrs, "spell_id")
    boss_encounter_id = map_get(attrs, "boss_encounter_id")
    difficulty_id = map_get(attrs, "difficulty_id")

    query =
      MechanicCriterion
      |> where([c], c.ruleset_id == ^ruleset_id and c.spell_id == ^spell_id)

    query =
      if is_nil(boss_encounter_id) do
        where(query, [c], is_nil(c.boss_encounter_id))
      else
        where(query, [c], c.boss_encounter_id == ^boss_encounter_id)
      end

    query =
      if is_nil(difficulty_id) do
        where(query, [c], is_nil(c.difficulty_id))
      else
        where(query, [c], c.difficulty_id == ^difficulty_id)
      end

    Repo.one(query)
  end

  defp map_get(map, key, default \\ nil)
  defp map_get(map, key, default) when is_map_key(map, key), do: Map.get(map, key, default)

  defp map_get(map, key, default) when is_binary(key) do
    Map.get(map, String.to_existing_atom(key), default)
  rescue
    ArgumentError -> default
  end
end
