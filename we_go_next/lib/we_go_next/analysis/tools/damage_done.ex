defmodule WeGoNext.Analysis.Tools.DamageDone do
  @moduledoc "Compact per-pull player damage with authored target classes and bounded evidence samples."
  @behaviour WeGoNext.Analysis.Tool
  import Ecto.Query
  alias WeGoNext.Analysis.{PullScope, Result}
  alias WeGoNext.GameData.Raids.DamageTargets
  alias WeGoNext.Repo
  alias WeGoNext.Silver.{DamageDone, PlayerInfo}

  def name, do: "damage_done"

  def description do
    "Per player per gold pull in the session log: total_damage, boss_damage, priority_damage, other_damage and class shares of that player's total (0..1). Pets are already owner-attributed in silver. player matches exact name or GUID. target_class (boss, priority, other) selects players with positive damage in that class; totals and share denominators ALWAYS retain all targets. Evidence contains one largest target/spell aggregate per nonempty class, not a complete spell breakdown; timestamp is pull start, not hit time. Other includes unknown targets and is NOT proof of padding. Unverified/missing catalogs are explicit. No time windows, DPS ranking or population percentiles. Follow next_cursor with identical filters."
  end

  def input_schema do
    PullScope.schema("pulls", %{
      "player" => %{"type" => "string", "minLength" => 1},
      "target_class" => %{"type" => "string", "enum" => ["boss", "priority", "other"]}
    })
  end

  def run(args, session) do
    with {:ok, pulls} <- PullScope.fetch(args["pulls"], session) do
      ids = Enum.map(pulls, & &1.pull_id)

      rows =
        from(d in DamageDone,
          left_join: p in PlayerInfo,
          on: p.encounter_dim_id == d.encounter_dim_id and p.player_guid == d.source_guid,
          where: d.encounter_dim_id in ^ids,
          select: %{
            pull_id: d.encounter_dim_id,
            player_guid: d.source_guid,
            player_name: p.player_name,
            target_guid: d.target_guid,
            spell_id: d.spell_id,
            total_amount: d.total_amount
          }
        )
        |> filter_player(args["player"])
        |> Repo.all()
        |> Enum.group_by(& &1.pull_id)

      pairs = Enum.flat_map(pulls, &summaries(&1, Map.get(rows, &1.pull_id, []), args))
      Result.page(pairs, args, {name(), session.id})
    end
  end

  defp summaries(pull, rows, args) do
    targets = DamageTargets.for_encounter(pull.boss_id)

    rows
    |> Enum.group_by(& &1.player_guid)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {guid, hits} -> summarize(pull, guid, hits, targets) end)
    |> Enum.filter(fn {row, _} -> matches_class?(row, args["target_class"]) end)
  end

  defp summarize(pull, guid, hits, targets) do
    classes = Enum.group_by(hits, &DamageTargets.classify(&1.target_guid, targets))
    boss = amount(classes, :boss)
    priority = amount(classes, :priority)
    other = amount(classes, :other)
    total = boss + priority + other

    row = %{
      pull_id: pull.pull_id,
      player_guid: guid,
      player_name: hd(hits).player_name,
      total_damage: total,
      boss_damage: boss,
      priority_damage: priority,
      other_damage: other,
      boss_share: share(boss, total),
      priority_share: share(priority, total),
      other_share: share(other, total),
      targets_verified: targets.verified
    }

    evidence =
      PullScope.evidence(pull, "silver.damage_done")
      |> Map.put(:target_catalog, targets)
      |> Map.put(:samples, samples(classes))

    {row, evidence}
  end

  defp samples(classes) do
    for class <- [:boss, :priority, :other], hits = Map.get(classes, class, []), hits != [] do
      hit = Enum.min_by(hits, &{-&1.total_amount, &1.target_guid, &1.spell_id})
      hit |> Map.take([:target_guid, :spell_id, :total_amount]) |> Map.put(:target_class, class)
    end
  end

  defp amount(classes, key), do: classes |> Map.get(key, []) |> Enum.sum_by(& &1.total_amount)
  defp share(_, 0), do: 0.0
  defp share(value, total), do: value / total
  defp matches_class?(_, nil), do: true
  defp matches_class?(row, "boss"), do: row.boss_damage > 0
  defp matches_class?(row, "priority"), do: row.priority_damage > 0
  defp matches_class?(row, "other"), do: row.other_damage > 0
  defp filter_player(query, nil), do: query

  defp filter_player(query, player),
    do: where(query, [d, p], d.source_guid == ^player or p.player_name == ^player)
end
