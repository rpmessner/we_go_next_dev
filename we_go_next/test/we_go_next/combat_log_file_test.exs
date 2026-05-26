defmodule WeGoNext.CombatLogFileTest do
  use ExUnit.Case, async: true

  alias WeGoNext.CombatLogFile

  test "changeset defaults source to live" do
    changeset =
      CombatLogFile.changeset(%CombatLogFile{}, %{
        file_path: "/tmp/WoWCombatLog-test.txt",
        user_id: 1
      })

    assert changeset.valid?
    assert Ecto.Changeset.apply_changes(changeset).source == :live
  end

  test "changeset accepts supported sources" do
    base_attrs = %{file_path: "/tmp/WoWCombatLog-test.txt", user_id: 1}

    assert %{valid?: true} =
             CombatLogFile.changeset(%CombatLogFile{}, Map.put(base_attrs, :source, :live))

    assert %{valid?: true} =
             CombatLogFile.changeset(
               %CombatLogFile{},
               Map.put(base_attrs, :source, "warcraftlogs_archive")
             )
  end

  test "changeset rejects unsupported sources" do
    changeset =
      CombatLogFile.changeset(%CombatLogFile{}, %{
        file_path: "/tmp/WoWCombatLog-test.txt",
        user_id: 1,
        source: "other"
      })

    refute changeset.valid?
    assert {"is invalid", _} = Keyword.fetch!(changeset.errors, :source)
  end

  test "changeset validates head_sha256 shape when present" do
    changeset =
      CombatLogFile.changeset(%CombatLogFile{}, %{
        file_path: "/tmp/WoWCombatLog-test.txt",
        user_id: 1,
        head_sha256: "not-a-hash"
      })

    refute changeset.valid?
    assert {"has invalid format", _} = Keyword.fetch!(changeset.errors, :head_sha256)
  end

  test "attrs_from_file includes source and head_sha256" do
    dir = temp_dir!()
    file_path = Path.join(dir, "Archive-WoWCombatLog-test.txt")
    content = "COMBAT_LOG_VERSION,22\n" <> String.duplicate("x", 5_000)
    File.write!(file_path, content)

    assert {:ok, attrs} =
             CombatLogFile.attrs_from_file(file_path, 42, source: :warcraftlogs_archive)

    assert attrs.file_path == file_path
    assert attrs.file_size == byte_size(content)
    assert attrs.source == :warcraftlogs_archive
    assert attrs.user_id == 42
    assert attrs.last_parsed_byte == 0
    assert attrs.head_sha256 == sha256(binary_part(content, 0, 4_096))
  end

  test "attrs_from_file infers warcraftlogs archive source from archive filename" do
    dir = temp_dir!()
    file_path = Path.join(dir, "Archive-WoWCombatLog-test.txt")
    File.write!(file_path, "archived combat log")

    assert {:ok, attrs} = CombatLogFile.attrs_from_file(file_path, 42)
    assert attrs.source == :warcraftlogs_archive
  end

  defp temp_dir! do
    dir =
      Path.join(System.tmp_dir!(), "wgn-combat-log-file-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp sha256(data) do
    :sha256
    |> :crypto.hash(data)
    |> Base.encode16(case: :lower)
  end
end
