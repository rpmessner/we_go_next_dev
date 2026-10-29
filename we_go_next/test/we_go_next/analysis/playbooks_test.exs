defmodule WeGoNext.Analysis.PlaybooksTest do
  use ExUnit.Case, async: true
  alias WeGoNext.Analysis.Playbooks

  defp file(scope, ids, status \\ "active") do
    """
    ---
    title: Between pulls
    scope: #{scope}
    encounter_ids: #{ids}
    question_families: ["wipes", "deaths"]
    status: #{status}
    ---
    Check the first death.
    """
  end

  test "parses reviewed Markdown and selects active global and matching boss Playbooks" do
    assert {:ok, global} = Playbooks.parse("general", file("global", "[]"))
    assert {:ok, boss} = Playbooks.parse("boss", file("boss", "[42]"))
    assert {:ok, retired} = Playbooks.parse("old", file("global", "[]", "retired"))
    assert global.body == "Check the first death.\n"
    assert Playbooks.select([global, boss, retired], [42]) == [global, boss]
    assert Playbooks.select([global, boss, retired], []) == [global]
  end

  test "matches boss names through log pulls and ids without a pull" do
    {:ok, boss} = Playbooks.parse("boss", file("boss", "[42]"))
    pulls = [%{boss: "Sszorak", boss_id: "42"}, %{boss: "Unknown", boss_id: nil}]
    assert Playbooks.for_boss([boss], "Sszorak", pulls) == [boss]
    assert Playbooks.for_boss([boss], "42", []) == [boss]
    assert Playbooks.for_boss([boss], nil, pulls) == []
    assert Playbooks.for_boss([boss], "Unknown", pulls) == []
  end

  test "missing git metadata does not prevent an Analysis session" do
    assert Playbooks.git_commit("/tmp/nonexistent-playbook-dir/book.md") == nil
  end

  test "rejects invalid metadata instead of loading ambiguous instructions" do
    assert {:error, _} = Playbooks.parse("bad", file("boss", "[]"))

    assert {:error, _} =
             Playbooks.parse("bad", file("global", "[]") |> String.replace("wipes", "unknown"))

    assert {:error, _} = Playbooks.parse("bad", "No front matter")
  end
end
