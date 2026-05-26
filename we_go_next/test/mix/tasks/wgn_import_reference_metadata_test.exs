defmodule Mix.Tasks.Wgn.ImportReferenceMetadataTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Wgn.ImportReferenceMetadata
  alias WeGoNext.Repo
  alias WeGoNext.SourceData.{EncounterReference, EncounterSpellReference, SpellReference}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
    end)

    :ok
  end

  test "imports reference metadata from explicit files and reports counts" do
    path =
      write_json_fixture(%{
        "spells" => [%{"spell_id" => 1_249_017, "name" => "Fearsome Cry"}],
        "encounters" => [
          %{
            "encounter_id" => 3306,
            "name" => "Chimaerus",
            "difficulty_id" => 16,
            "spell_ids" => [1_249_017]
          }
        ]
      })

    output =
      capture_task_output(fn ->
        ImportReferenceMetadata.run([
          "--file",
          path,
          "--build-key",
          "11.2.5",
          "--channel",
          "ptr"
        ])
      end)

    assert output =~ "Imported reference metadata from 1 file(s)"
    assert output =~ "1 spell(s) inserted"
    assert output =~ "1 encounter(s) inserted"
    assert output =~ "1 encounter-spell link(s) inserted"

    assert Repo.aggregate(SpellReference, :count) == 1
    assert Repo.aggregate(EncounterReference, :count) == 1
    assert Repo.aggregate(EncounterSpellReference, :count) == 1
  end

  test "requires build key" do
    path = write_json_fixture(%{"1214081" => "Arcane Expulsion"})

    assert_raise Mix.Error, ~r/requires --build-key/, fn ->
      ImportReferenceMetadata.run(["--spell-file", path])
    end
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

  defp write_json_fixture(payload) do
    directory =
      Path.join(System.tmp_dir!(), "wgn-reference-task-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    path = Path.join(directory, "reference.json")
    File.write!(path, Jason.encode!(payload))

    on_exit(fn -> File.rm_rf(directory) end)

    path
  end
end
