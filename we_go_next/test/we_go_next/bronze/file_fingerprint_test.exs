defmodule WeGoNext.Bronze.FileFingerprintTest do
  use ExUnit.Case, async: true

  alias WeGoNext.Bronze.FileFingerprint

  test "head_sha256 hashes only the first 4 KB" do
    dir = temp_dir!()
    file_path = Path.join(dir, "WoWCombatLog-test.txt")
    content = String.duplicate("a", 4_096) <> "different tail"
    File.write!(file_path, content)

    expected =
      content
      |> binary_part(0, 4_096)
      |> sha256()

    assert FileFingerprint.head_sha256(file_path) == {:ok, expected}
    refute FileFingerprint.head_sha256(file_path) == {:ok, sha256(content)}
  end

  test "head_sha256 returns file errors" do
    assert {:error, :enoent} = FileFingerprint.head_sha256("/missing/wow/log.txt")
  end

  defp temp_dir! do
    dir = Path.join(System.tmp_dir!(), "wgn-fingerprint-#{System.unique_integer([:positive])}")
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
