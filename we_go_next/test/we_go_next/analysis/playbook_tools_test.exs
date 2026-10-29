defmodule WeGoNext.Analysis.PlaybookToolsTest do
  use WeGoNext.DataCase, async: false
  alias WeGoNext.{Analysis, Repo}
  alias WeGoNext.Analysis.{Arguments, Playbooks, Session, ToolCall}
  alias WeGoNext.Analysis.Tools.{GetPlaybook, ListPlaybooks}

  setup do
    user = Repo.insert!(%WeGoNext.Accounts.User{name: "playbooks"})

    log =
      Repo.insert!(%WeGoNext.CombatLogFile{
        user_id: user.id,
        file_path: "/playbooks.txt",
        last_parsed_at: ~U[2026-09-06 12:00:00Z]
      })

    {:ok, session} = Analysis.start_session(%{"log" => to_string(log.id)})
    {:ok, session: session}
  end

  test "sessions inserted by the old schema shape default to no loaded Playbooks", %{
    session: session
  } do
    id = Ecto.UUID.generate()

    Repo.query!(
      "INSERT INTO analysis.sessions (id, started_at, combat_log_file_id) VALUES ($1, $2, $3)",
      [Ecto.UUID.dump!(id), DateTime.utc_now(), session.combat_log_file_id]
    )

    assert Repo.get!(Session, id).loaded_playbooks == []
  end

  test "lists matching active metadata with version evidence", %{session: session} do
    assert {:ok, result} = ListPlaybooks.run(%{"question_family" => "wipes"}, session)
    assert [%{id: "between-pulls", title: "Between-pull method"}] = result.data
    assert [%{playbook_id: "between-pulls", git_commit: commit}] = result.evidence
    assert commit == Playbooks.git_commit(Playbooks.directory())
    assert byte_size(Jason.encode!(result)) <= 8192

    assert :ok =
             Arguments.validate(
               %{"session_id" => session.id, "question_family" => "own-play"},
               ListPlaybooks.input_schema()
             )

    assert {:error, _} =
             Arguments.validate(
               %{"session_id" => session.id, "question_family" => "other"},
               ListPlaybooks.input_schema()
             )
  end

  test "large Playbooks paginate without losing Markdown", %{session: session} do
    path = Path.join(Playbooks.directory(), "test-large.md")
    on_exit(fn -> File.rm!(path) end)
    body = String.duplicate("Inspect evidence.\n", 2000)

    File.write!(
      path,
      """
      ---
      title: Large test
      scope: boss
      encounter_ids: [99]
      question_families: ["coaching"]
      status: active
      ---
      """ <> body
    )

    args = %{"id" => "test-large"}
    assert {:ok, page} = GetPlaybook.run(args, session)
    assert page.truncated
    assert drain(page, args, session) == body
  end

  defp drain(page, args, session) do
    assert byte_size(Jason.encode!(page)) <= 8192
    body = Enum.map_join(page.data, & &1.body)

    if page.truncated do
      assert {:ok, next} = GetPlaybook.run(Map.put(args, "cursor", page.next_cursor), session)
      body <> drain(next, args, session)
    else
      assert page.next_cursor == nil
      body
    end
  end

  test "fetches Markdown through the bounded Tool and records the loaded version", %{
    session: session
  } do
    Repo.update_all(Session, set: [loaded_playbooks: []])

    assert {:ok, result} =
             Analysis.call_tool("get_playbook", %{
               "session_id" => session.id,
               "id" => "between-pulls"
             })

    assert [%{id: "between-pulls", body: body}] = result.data
    assert body =~ "# Between-pull method"

    assert [%{"id" => "between-pulls", "git_commit" => commit}] =
             Repo.get!(Session, session.id).loaded_playbooks

    assert commit == Playbooks.git_commit(Playbooks.directory())
    assert Repo.one!(ToolCall).tool == "get_playbook"
    assert {:error, _} = GetPlaybook.run(%{"id" => "../analyst"}, session)
    assert {:error, _} = GetPlaybook.run(%{"id" => "absent"}, session)
  end
end
