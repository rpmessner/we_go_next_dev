defmodule WeGoNext.Rules do
  @moduledoc """
  Context for authored mechanic rules.

  Rules are business configuration. They remain independent from legacy public
  criteria tables and from gold snapshots until an explicit promotion step.
  """

  import Ecto.Query

  alias WeGoNext.Gold.DimMechanicCriterion
  alias WeGoNext.Repo
  alias WeGoNext.Rules.{MechanicCriterion, Ruleset}

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
  def promote_ruleset_to_gold(%Ruleset{} = ruleset) do
    Repo.transaction(fn ->
      ruleset = Repo.preload(ruleset, :mechanic_criteria)

      promoted =
        ruleset.mechanic_criteria
        |> Enum.sort_by(& &1.id)
        |> Enum.reduce_while([], fn criterion, promoted ->
          case upsert_gold_mechanic_criterion(ruleset, criterion) do
            {:ok, snapshot} -> {:cont, [snapshot | promoted]}
            {:error, changeset} -> {:halt, Repo.rollback(changeset)}
          end
        end)
        |> Enum.reverse()

      %{ruleset: ruleset, criteria: promoted}
    end)
  end

  def promote_ruleset_to_gold(ruleset_id) do
    ruleset_id
    |> get_ruleset!()
    |> promote_ruleset_to_gold()
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
  Seeds the bundled initial mechanic rules JSON.
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
  def seed_rules_from_file(path) when is_binary(path) do
    with {:ok, body} <- File.read(path),
         {:ok, payload} <- Jason.decode(body) do
      seed_rules(payload)
    end
  end

  def seed_rules(%{} = payload) do
    Repo.transaction(fn ->
      ruleset_attrs = map_get(payload, "ruleset", %{})
      criteria = map_get(payload, "criteria", [])

      with {:ok, ruleset} <- get_or_create_seed_ruleset(ruleset_attrs),
           {:ok, seeded_criteria} <- seed_mechanic_criteria(ruleset, criteria) do
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

  defp ruleset_seed_attrs(attrs) do
    %{
      name: map_get(attrs, "name"),
      version: map_get(attrs, "version", 1),
      status: map_get(attrs, "status", "draft")
    }
  end

  defp seed_mechanic_criteria(%Ruleset{} = ruleset, criteria) when is_list(criteria) do
    criteria
    |> Enum.reduce_while({:ok, []}, fn attrs, {:ok, seeded} ->
      case upsert_seed_mechanic_criterion(ruleset, attrs) do
        {:ok, criterion} -> {:cont, {:ok, [criterion | seeded]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, seeded} -> {:ok, Enum.reverse(seeded)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp seed_mechanic_criteria(_ruleset, _criteria), do: {:error, :invalid_criteria}

  defp upsert_seed_mechanic_criterion(%Ruleset{} = ruleset, attrs) when is_map(attrs) do
    attrs = Map.put(attrs, "ruleset_id", ruleset.id)

    case get_seed_mechanic_criterion(ruleset.id, attrs) do
      %MechanicCriterion{} = criterion -> update_mechanic_criterion(criterion, attrs)
      nil -> create_mechanic_criterion(attrs)
    end
  end

  defp upsert_seed_mechanic_criterion(_ruleset, _attrs), do: {:error, :invalid_criterion}

  defp upsert_gold_mechanic_criterion(%Ruleset{} = ruleset, %MechanicCriterion{} = criterion) do
    attrs = gold_snapshot_attrs(ruleset, criterion)

    %DimMechanicCriterion{}
    |> DimMechanicCriterion.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :ruleset_id,
           :ruleset_version,
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

  defp gold_snapshot_attrs(%Ruleset{} = ruleset, %MechanicCriterion{} = criterion) do
    %{
      source_rule_id: criterion.id,
      ruleset_id: ruleset.id,
      ruleset_version: ruleset.version,
      spell_id: criterion.spell_id,
      spell_name: criterion.spell_name,
      mechanic_type: criterion.mechanic_type,
      boss_encounter_id: criterion.boss_encounter_id,
      boss_name: criterion.boss_name,
      difficulty_id: criterion.difficulty_id,
      threshold: criterion.threshold,
      notes: criterion.notes,
      active: criterion.active
    }
  end

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
