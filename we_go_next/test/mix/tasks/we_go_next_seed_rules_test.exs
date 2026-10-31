defmodule Mix.Tasks.WeGoNext.SeedRulesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.WeGoNext.SeedRules
  alias WeGoNext.Gold.{DimMechanicCriterion, FactFailure}
  alias WeGoNext.Repo
  alias WeGoNext.Rules.{MechanicCriterion, Ruleset}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Mix.shell(Mix.Shell.Process)

    Repo.delete_all(FactFailure)
    Repo.delete_all(DimMechanicCriterion)
    Repo.delete_all(MechanicCriterion)
    Repo.delete_all(Ruleset)

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
    end)

    :ok
  end

  test "defaults to current-tier raid catalog mechanics" do
    output = capture_task_output(fn -> SeedRules.run([]) end)

    assert output =~
             "Synced 32 mechanic definition(s) into Midnight Current Tier Mechanics v1."

    assert Repo.get_by(Ruleset, name: "Midnight Current Tier Mechanics", version: 1)
    refute Repo.get_by(Ruleset, name: "Initial Mechanic Rules", version: 1)

    assert 32 =
             MechanicCriterion
             |> Repo.aggregate(:count)
  end

  test "default seed and raid sync commands preserve an activated ruleset" do
    {:ok, %{ruleset: active}} = WeGoNext.Rules.sync_current_tier_rules(activate: true)

    capture_task_output(fn -> SeedRules.run([]) end)
    assert WeGoNext.Rules.get_ruleset!(active.id).status == "active"
    assert WeGoNext.Rules.get_ruleset!(active.id).activated_at == active.activated_at

    capture_task_output(fn -> Mix.Tasks.WeGoNext.SyncRaidRules.run([]) end)
    assert WeGoNext.Rules.get_ruleset!(active.id).status == "active"
    assert WeGoNext.Rules.get_ruleset!(active.id).activated_at == active.activated_at
  end

  test "raid sync CLI names the failed stage and committed work" do
    assert_raise Mix.Error, ~r/failed at sync.*Committed stages: \[\]/, fn ->
      Mix.Tasks.WeGoNext.SyncRaidRules.run(["not-a-raid", "--rebuild"])
    end
  end

  test "still accepts explicit static JSON paths for legacy fixtures" do
    path =
      Path.join(System.tmp_dir!(), "wgn-legacy-rules-#{System.unique_integer([:positive])}.json")

    payload = %{
      "ruleset" => %{"name" => "Legacy Fixture Rules", "version" => 1, "status" => "draft"},
      "criteria" => [
        %{
          "spell_id" => 999_001,
          "spell_name" => "Legacy Avoid",
          "mechanic_type" => "avoidable",
          "threshold" => %{"max_hits" => 0}
        }
      ]
    }

    File.write!(path, Jason.encode!(payload))
    on_exit(fn -> File.rm(path) end)

    output = capture_task_output(fn -> SeedRules.run([path]) end)

    assert output =~ "Synced 1 mechanic definition(s) into Legacy Fixture Rules v1."
    assert Repo.get_by(Ruleset, name: "Legacy Fixture Rules", version: 1)
  end

  defp capture_task_output(fun) do
    capture_io(fn ->
      fun.()
      flush_shell_messages()
    end)
  end

  defp flush_shell_messages do
    receive do
      {:mix_shell, :info, [message]} ->
        IO.puts(message)
        flush_shell_messages()
    after
      0 -> :ok
    end
  end
end
