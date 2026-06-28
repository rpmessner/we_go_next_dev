defmodule WeGoNext.AccountsTest do
  use ExUnit.Case, async: false

  alias WeGoNext.Accounts
  alias WeGoNext.Accounts.User
  alias WeGoNext.{CombatLogFile, Repo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    dir = Path.join(System.tmp_dir!(), "wgn-accounts-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    user =
      Repo.insert!(%User{
        name: "user-#{System.unique_integer([:positive])}",
        wow_logs_path: dir
      })

    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, dir: dir, user: user}
  end

  test "list_combat_logs backfills missing head_sha256 for existing rows", %{dir: dir, user: user} do
    file_path = Path.join(dir, "WoWCombatLog-test.txt")
    content = "COMBAT_LOG_VERSION,22\nfirst event\n"
    File.write!(file_path, content)

    combat_log_file =
      %CombatLogFile{}
      |> CombatLogFile.changeset(%{
        file_path: file_path,
        file_size: byte_size(content),
        file_mtime: DateTime.utc_now() |> DateTime.truncate(:second),
        source: :live,
        user_id: user.id,
        last_parsed_byte: 0
      })
      |> Repo.insert!()

    assert combat_log_file.head_sha256 == nil

    assert {:ok, [%{full_path: ^file_path, source: :live}]} = Accounts.list_combat_logs(user)

    assert Repo.get!(CombatLogFile, combat_log_file.id).head_sha256 == sha256(content)
  end

  test "list_combat_logs includes live and warcraftlogs archive files", %{dir: dir, user: user} do
    archive_dir = Path.join(dir, "warcraftlogsarchive")
    File.mkdir_p!(archive_dir)

    live_path = Path.join(dir, "WoWCombatLog-051626_111133.txt")
    archive_path = Path.join(archive_dir, "Archive-WoWCombatLog-051326_214806.txt")

    File.write!(live_path, "live log")
    File.write!(archive_path, "archive log")
    File.write!(Path.join(dir, "NotACombatLog.txt"), "ignore me")
    File.write!(Path.join(archive_dir, "WoWCombatLog-should-not-match.txt"), "ignore me")

    assert {:ok, logs} = Accounts.list_combat_logs(user)
    assert Enum.map(logs, & &1.full_path) == [live_path, archive_path]

    logs_by_path = Map.new(logs, &{&1.full_path, &1})

    assert Map.keys(logs_by_path) |> Enum.sort() == Enum.sort([archive_path, live_path])

    assert %{
             filename: "WoWCombatLog-051626_111133.txt",
             filename_datetime: ~N[2026-05-16 11:11:33],
             source: :live
           } = logs_by_path[live_path]

    assert %{
             filename: "Archive-WoWCombatLog-051326_214806.txt",
             filename_datetime: ~N[2026-05-13 21:48:06],
             source: :warcraftlogs_archive
           } = logs_by_path[archive_path]
  end

  test "Warcraft Logs API key is encrypted before storage", %{user: user} do
    assert {:ok, updated} =
             Accounts.set_warcraft_logs_credentials(user, "Local WCL Client", "secret-api-key")

    assert updated.warcraft_logs_client_name == "Local WCL Client"
    assert updated.warcraft_logs_api_key_set_at
    refute updated.warcraft_logs_api_key_encrypted == "secret-api-key"
    refute updated.warcraft_logs_api_key_encrypted =~ "secret"
    assert {:ok, "secret-api-key"} = Accounts.warcraft_logs_api_key(updated)
    assert Accounts.warcraft_logs_credentials_configured?(updated)

    assert {:ok, renamed} =
             Accounts.update_warcraft_logs_client_name(updated, "Renamed WCL Client")

    assert renamed.warcraft_logs_client_name == "Renamed WCL Client"
    assert renamed.warcraft_logs_api_key_encrypted == updated.warcraft_logs_api_key_encrypted

    assert {:ok, cleared} = Accounts.clear_warcraft_logs_credentials(renamed)
    refute Accounts.warcraft_logs_credentials_configured?(cleared)
    assert Accounts.warcraft_logs_api_key(cleared) == :error
  end

  test "mirror ingest token is encrypted before storage", %{user: user} do
    assert {:ok, updated} =
             Accounts.set_mirror_upload_settings(
               user,
               "https://public.example",
               "secret-ingest-token"
             )

    assert updated.mirror_public_base_url == "https://public.example"
    assert updated.mirror_ingest_token_set_at
    refute updated.mirror_ingest_token_encrypted == "secret-ingest-token"
    refute updated.mirror_ingest_token_encrypted =~ "secret"
    assert {:ok, "secret-ingest-token"} = Accounts.mirror_ingest_token(updated)
    assert Accounts.mirror_upload_configured?(updated)

    assert {:ok, cleared} = Accounts.clear_mirror_upload_settings(updated)
    refute Accounts.mirror_upload_configured?(cleared)
    assert Accounts.mirror_ingest_token(cleared) == :error
  end

  defp sha256(data) do
    :sha256
    |> :crypto.hash(data)
    |> Base.encode16(case: :lower)
  end
end
