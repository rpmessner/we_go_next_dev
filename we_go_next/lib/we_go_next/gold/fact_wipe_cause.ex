defmodule WeGoNext.Gold.FactWipeCause do
  @moduledoc "Deciding deaths, not proof that the first loss caused the eventual wipe."
  use Ecto.Schema
  import Ecto.Query

  alias WeGoNext.GameData.Raids
  alias WeGoNext.Gold.DimEncounter
  alias WeGoNext.Repo
  alias WeGoNext.Silver.{Death, PlayerInfo}

  @primary_key false
  @schema_prefix "gold"
  @derivation_version 1

  schema "fact_wipe_cause" do
    field(:encounter_dim_id, :integer, primary_key: true)
    field(:rank, :integer, primary_key: true)
    field(:player_guid, :string)
    field(:player_name, :string)
    field(:died_at_ms_into_fight, :integer)
    field(:killing_blow_spell_id, :integer)
    field(:killing_blow_spell_name, :string)
    field(:killing_blow_source_guid, :string)
    field(:killing_blow_source_name, :string)
    field(:mechanic_name, :string)
    field(:mechanic_type, :string)
    field(:avoidable, :boolean)
    field(:derivation_version, :integer)
    field(:rebuilt_at, :utc_datetime_usec)
  end

  def current_version, do: @derivation_version

  @doc "Pure derivation. Strictly before end minus 30s; ties break by player GUID."
  def deciding_deaths(encounter, deaths) do
    if encounter.success == false and is_integer(encounter.fight_time_ms) and
         encounter.fight_time_ms >= 10_000 do
      deaths
      |> Enum.filter(
        &(&1.died_at_ms_into_fight < encounter.fight_time_ms - 30_000 and
            String.starts_with?(&1.target_guid, "Player-"))
      )
      |> Enum.sort_by(&{&1.died_at_ms_into_fight, &1.target_guid})
      |> Enum.take(3)
    else
      []
    end
  end

  def rebuild_for_encounter(id) do
    Repo.transaction(fn ->
      # Serializes rebuilds even when there are no fact rows to lock.
      encounter = Repo.one!(from(e in DimEncounter, where: e.id == ^id, lock: "FOR UPDATE"))
      deaths = Repo.all(from(d in Death, where: d.encounter_dim_id == ^id))
      players = Repo.all(from(p in PlayerInfo, where: p.encounter_dim_id == ^id))
      names = Map.new(players, &{&1.player_guid, &1.player_name})
      now = DateTime.utc_now()

      rows =
        encounter
        |> deciding_deaths(deaths)
        |> Enum.with_index(1)
        |> Enum.map(fn {death, rank} ->
          death
          |> attributes(encounter, names)
          |> Map.merge(%{rank: rank, derivation_version: current_version(), rebuilt_at: now})
        end)

      {deleted, _} = Repo.delete_all(from(f in __MODULE__, where: f.encounter_dim_id == ^id))
      {inserted, _} = Repo.insert_all(__MODULE__, rows)

      encounter
      |> Ecto.Changeset.change(wipe_cause_derivation_version: current_version())
      |> Repo.update!()

      %{deleted: deleted, inserted: inserted}
    end)
  end

  def rows(ids) do
    Repo.all(
      from(f in __MODULE__,
        where: f.encounter_dim_id in ^ids,
        order_by: [f.encounter_dim_id, f.rank]
      )
    )
    |> Enum.map(&Map.from_struct/1)
    |> Enum.map(&Map.delete(&1, :__meta__))
  end

  defp attributes(death, encounter, names) do
    blow = List.first(death.damage_recap) || %{}
    mechanic = mechanic(encounter.wow_encounter_id, death.killing_blow_spell_id)

    %{
      encounter_dim_id: encounter.id,
      player_guid: death.target_guid,
      player_name: names[death.target_guid],
      died_at_ms_into_fight: death.died_at_ms_into_fight,
      killing_blow_spell_id: death.killing_blow_spell_id,
      killing_blow_spell_name: blow["spell_name"],
      killing_blow_source_guid: death.killing_blow_source_guid,
      killing_blow_source_name: blow["source_name"],
      mechanic_name: mechanic && mechanic.name,
      mechanic_type: mechanic && to_string(mechanic.mechanic_type),
      avoidable: avoidable(mechanic)
    }
  end

  defp mechanic(boss_id, spell_id) do
    case Raids.by_boss_encounter_id(boss_id) do
      nil ->
        nil

      raid ->
        Enum.find(
          raid.mechanics(),
          &(to_string(&1.boss_encounter_id) == boss_id and
              &1.spell_id == spell_id and &1.evidence_family == :damage_taken)
        )
    end
  end

  defp avoidable(nil), do: nil
  defp avoidable(%{mechanic_type: :unknown}), do: nil
  defp avoidable(%{mechanic_type: :avoidable}), do: true
  defp avoidable(_), do: false
end
