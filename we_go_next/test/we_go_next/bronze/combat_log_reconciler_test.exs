defmodule WeGoNext.Bronze.CombatLogReconcilerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias WeGoNext.Accounts
  alias WeGoNext.Accounts.User
  alias WeGoNext.Bronze.CombatLogReconciler
  alias WeGoNext.{CombatLogFile, Importer, Repo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    dir = Path.join(System.tmp_dir!(), "wgn-reconciler-#{System.unique_integer([:positive])}")
    archive_dir = Path.join(dir, "warcraftlogsarchive")
    File.mkdir_p!(archive_dir)

    user =
      Repo.insert!(%User{
        name: "user-#{System.unique_integer([:positive])}",
        wow_logs_path: dir
      })

    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, dir: dir, archive_dir: archive_dir, user: user}
  end

  test "reconcile_archive_move updates matching live row without changing progress", %{
    dir: dir,
    archive_dir: archive_dir,
    user: user
  } do
    content = "COMBAT_LOG_VERSION,22\n" <> String.duplicate("same head\n", 600)
    live_path = Path.join(dir, "WoWCombatLog-051626_111133.txt")
    archive_path = Path.join(archive_dir, "Archive-WoWCombatLog-051626_111133.txt")
    File.write!(archive_path, content <> "archive tail")

    live =
      insert_combat_log_file!(%{
        file_path: live_path,
        file_size: byte_size(content),
        source: :live,
        user_id: user.id,
        last_parsed_byte: 123,
        head_sha256: sha256(binary_part(content, 0, min(byte_size(content), 4_096)))
      })

    assert {:ok, updated} = CombatLogReconciler.reconcile_archive_move(archive_path, user.id)

    assert updated.id == live.id
    assert updated.file_path == archive_path
    assert updated.source == :warcraftlogs_archive
    assert updated.last_parsed_byte == 123
    assert updated.file_size == byte_size(content <> "archive tail")
    assert updated.head_sha256 == live.head_sha256
  end

  test "reconcile_archive_move does not match when fingerprint differs", %{
    dir: dir,
    archive_dir: archive_dir,
    user: user
  } do
    live_path = Path.join(dir, "WoWCombatLog-051626_111133.txt")
    archive_path = Path.join(archive_dir, "Archive-WoWCombatLog-051626_111133.txt")
    File.write!(archive_path, "different archive content")

    live =
      insert_combat_log_file!(%{
        file_path: live_path,
        file_size: 1,
        source: :live,
        user_id: user.id,
        head_sha256: sha256("live content")
      })

    assert {:ok, nil} = CombatLogReconciler.reconcile_archive_move(archive_path, user.id)
    assert Repo.get!(CombatLogFile, live.id).file_path == live_path
  end

  test "reconcile_archive_move does not match when archive is smaller", %{
    dir: dir,
    archive_dir: archive_dir,
    user: user
  } do
    archive_content = "small"
    live_path = Path.join(dir, "WoWCombatLog-051626_111133.txt")
    archive_path = Path.join(archive_dir, "Archive-WoWCombatLog-051626_111133.txt")
    File.write!(archive_path, archive_content)

    insert_combat_log_file!(%{
      file_path: live_path,
      file_size: byte_size(archive_content) + 1,
      source: :live,
      user_id: user.id,
      head_sha256: sha256(archive_content)
    })

    assert {:ok, nil} = CombatLogReconciler.reconcile_archive_move(archive_path, user.id)
  end

  test "reconcile_archive_move allows weak fallback without head_sha256 and logs warning", %{
    dir: dir,
    archive_dir: archive_dir,
    user: user
  } do
    live_path = Path.join(dir, "WoWCombatLog-051626_111133.txt")
    archive_path = Path.join(archive_dir, "Archive-WoWCombatLog-051626_111133.txt")
    File.write!(archive_path, "archive content")

    live =
      insert_combat_log_file!(%{
        file_path: live_path,
        file_size: 1,
        source: :live,
        user_id: user.id,
        last_parsed_byte: 456
      })

    log =
      capture_log(fn ->
        assert {:ok, updated} = CombatLogReconciler.reconcile_archive_move(archive_path, user.id)
        assert updated.id == live.id
        assert updated.last_parsed_byte == 456
      end)

    assert log =~ "without head_sha256"
    assert Repo.get!(CombatLogFile, live.id).file_path == archive_path
  end

  test "Accounts discovery reconciles archive moves", %{
    dir: dir,
    archive_dir: archive_dir,
    user: user
  } do
    content = "COMBAT_LOG_VERSION,22\n"
    live_path = Path.join(dir, "WoWCombatLog-051626_111133.txt")
    archive_path = Path.join(archive_dir, "Archive-WoWCombatLog-051626_111133.txt")
    File.write!(archive_path, content)

    live =
      insert_combat_log_file!(%{
        file_path: live_path,
        file_size: byte_size(content),
        source: :live,
        user_id: user.id,
        last_parsed_byte: 12,
        head_sha256: sha256(content)
      })

    assert {:ok, [%{full_path: ^archive_path, source: :warcraftlogs_archive}]} =
             Accounts.list_combat_logs(user)

    updated = Repo.get!(CombatLogFile, live.id)
    assert updated.file_path == archive_path
    assert updated.source == :warcraftlogs_archive
    assert updated.last_parsed_byte == 12
  end

  test "Importer reuses reconciled archive row instead of inserting a new one", %{
    dir: dir,
    archive_dir: archive_dir,
    user: user
  } do
    content = "not a parseable combat log"
    live_path = Path.join(dir, "WoWCombatLog-051626_111133.txt")
    archive_path = Path.join(archive_dir, "Archive-WoWCombatLog-051626_111133.txt")
    File.write!(archive_path, content)

    live =
      insert_combat_log_file!(%{
        file_path: live_path,
        file_size: byte_size(content),
        source: :live,
        user_id: user.id,
        last_parsed_byte: 7,
        head_sha256: sha256(content)
      })

    assert {:ok, %{file: file, new_encounters: 0}} = Importer.import_log(archive_path, user.id)

    assert file.id == live.id
    assert file.file_path == archive_path
    assert Repo.aggregate(CombatLogFile, :count) == 1
  end

  defp insert_combat_log_file!(attrs) do
    attrs =
      Map.merge(
        %{
          file_size: 0,
          file_mtime: DateTime.utc_now() |> DateTime.truncate(:second),
          last_parsed_byte: 0
        },
        attrs
      )

    %CombatLogFile{}
    |> CombatLogFile.changeset(attrs)
    |> Repo.insert!()
  end

  defp sha256(data) do
    :sha256
    |> :crypto.hash(data)
    |> Base.encode16(case: :lower)
  end
end
