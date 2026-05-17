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

  defp sha256(data) do
    :sha256
    |> :crypto.hash(data)
    |> Base.encode16(case: :lower)
  end
end
