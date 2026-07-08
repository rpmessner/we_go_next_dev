defmodule WeGoNext.Documents.Store.FileSystem do
  @moduledoc """
  Minimal filesystem-backed store for generated encounter documents.
  """

  @encounters_dir "encounters"
  @index_file "index.json"

  @spec put_encounter(map()) :: {:ok, String.t()} | {:error, term()}
  def put_encounter(%{source_encounter_key: source_encounter_key} = document)
      when is_binary(source_encounter_key) do
    path = encounter_path(source_encounter_key)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- write_json(path, document) do
      {:ok, path}
    end
  end

  @spec refresh_index() :: {:ok, String.t()} | {:error, term()}
  def refresh_index do
    path = index_path()

    with {:ok, documents} <- encounter_documents(),
         :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <-
           write_json(path, %{
             schema_version: 1,
             generated_at: DateTime.utc_now(),
             encounters: index_entries(documents)
           }) do
      {:ok, path}
    end
  end

  def root do
    Application.fetch_env!(:we_go_next, :documents_root)
  end

  def encounter_path(source_encounter_key) do
    root()
    |> Path.join(@encounters_dir)
    |> Path.join("#{source_encounter_key}.json")
  end

  def index_path, do: Path.join(root(), @index_file)

  defp encounter_documents do
    encounters_root = Path.join(root(), @encounters_dir)

    case File.ls(encounters_root) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.map(&Path.join(encounters_root, &1))
        |> Enum.reduce_while({:ok, []}, fn path, {:ok, documents} ->
          case read_json(path) do
            {:ok, document} -> {:cont, {:ok, [document | documents]}}
            {:error, reason} -> {:halt, {:error, {path, reason}}}
          end
        end)

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp index_entries(documents) do
    documents
    |> Enum.map(&index_entry/1)
    |> Enum.sort_by(
      &{Map.get(&1, "start_time") || "", Map.get(&1, "source_encounter_key") || ""},
      :desc
    )
  end

  defp index_entry(document) do
    encounter = Map.fetch!(document, "encounter")
    counts = Map.get(document, "counts", %{})
    failure_counts = get_in(document, ["failure_preview", "counts"]) || %{}
    pull_review = Map.get(document, "pull_review", %{})

    %{
      source_encounter_key: Map.fetch!(document, "source_encounter_key"),
      boss: Map.get(encounter, "name"),
      wow_encounter_id: Map.get(encounter, "wow_encounter_id"),
      difficulty_id: Map.get(encounter, "difficulty_id"),
      difficulty_name: Map.get(encounter, "difficulty_name"),
      start_time: Map.get(encounter, "start_time"),
      end_time: Map.get(encounter, "end_time"),
      success: Map.get(encounter, "success"),
      fight_time_ms: Map.get(encounter, "fight_time_ms"),
      headline_counts: %{
        deaths: Map.get(counts, "deaths", 0),
        failures: Map.get(failure_counts, "failures", 0),
        failure_damage: Map.get(failure_counts, "damage", 0),
        players: Map.get(counts, "players", 0),
        low_damage: pull_review |> Map.get("low_dps", []) |> length()
      }
    }
  end

  defp write_json(path, payload) do
    case Jason.encode(payload) do
      {:ok, json} -> File.write(path, json)
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_json(path) do
    case File.read(path) do
      {:ok, body} -> Jason.decode(body)
      {:error, reason} -> {:error, reason}
    end
  end
end
