defmodule Mix.Tasks.Wgn.ExportAnalysis do
  @moduledoc """
  Exports an Analysis session or sessions started on a UTC date as JSONL.

      mix wgn.export_analysis --session UUID --transcript transcript.jsonl --output session.jsonl
      mix wgn.export_analysis --night 2026-09-06 --transcript-dir project-directory --output night.jsonl

  Repeat --transcript for sessions spanning multiple Claude Code transcripts.
  --transcript-dir reads top-level *.jsonl files, not subagent directories.
  The output must be a new file. Unmatched calls are retained and counted.
  """
  use Mix.Task
  import Ecto.Query
  alias WeGoNext.{CombatLogFile, Repo}
  alias WeGoNext.Analysis.{Export, Message, Session, ToolCall, Verdict}
  @shortdoc "Export recorded Analysis sessions as JSONL"

  @impl true
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          session: :string,
          night: :string,
          transcript: :keep,
          transcript_dir: :string,
          output: :string
        ]
      )

    if rest != [] or invalid != [], do: Mix.raise("Unknown export arguments")
    query = session_query(opts)
    output = opts[:output] || Mix.raise("--output is required")
    events = read_transcripts(opts)
    Mix.Task.run("app.start")
    sessions = Repo.all(query)
    if sessions == [], do: Mix.raise("No Analysis sessions match the selection")
    records = Enum.map(sessions, &export_session(&1, events))
    write_records(output, records)

    for record <- records do
      Mix.shell().info(
        "Analysis session #{record.session.id}: #{record.unmatched.transcript_calls} unmatched transcript calls, #{record.unmatched.server_calls} unmatched server rows, #{record.unmatched.unscoped_transcript_calls} unscoped transcript calls"
      )
    end
  end

  defp session_query(opts) do
    case {opts[:session], opts[:night]} do
      {id, nil} when is_binary(id) ->
        case Ecto.UUID.cast(id) do
          {:ok, id} -> from(s in Session, where: s.id == ^id)
          :error -> Mix.raise("--session must be a UUID")
        end

      {nil, date} when is_binary(date) ->
        date =
          case Date.from_iso8601(date) do
            {:ok, date} -> date
            _ -> Mix.raise("--night must be a UTC YYYY-MM-DD date")
          end

        start = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
        finish = DateTime.add(start, 86_400, :second)

        from(s in Session,
          where: s.started_at >= ^start and s.started_at < ^finish,
          order_by: [s.started_at, s.id]
        )

      _ ->
        Mix.raise("Choose exactly one of --session UUID or --night YYYY-MM-DD")
    end
  end

  defp read_transcripts(opts) do
    paths = Keyword.get_values(opts, :transcript)

    paths =
      case opts[:transcript_dir] do
        nil -> paths
        dir -> paths ++ Path.wildcard(Path.join(dir, "*.jsonl"))
      end

    paths
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
    |> Enum.flat_map(&read_transcript/1)
    |> Enum.sort_by(&(&1["timestamp"] || ""))
  end

  defp read_transcript(path) do
    path
    |> File.stream!()
    |> Stream.with_index(1)
    |> Enum.map(fn {line, number} ->
      case Jason.decode(line) do
        {:ok, event} when is_map(event) -> Map.put(event, "_source", %{path: path, line: number})
        _ -> Mix.raise("Invalid transcript JSON object at #{path}:#{number}")
      end
    end)
  end

  defp export_session(session, events) do
    calls = Repo.all(from(c in ToolCall, where: c.session_id == ^session.id, order_by: c.id))
    verdicts = Repo.all(from(v in Verdict, where: v.session_id == ^session.id, order_by: v.id))
    log = Repo.get!(CombatLogFile, session.combat_log_file_id)

    context = %{
      active_log: Map.take(log, [:id, :file_path, :source, :raid_night_name]),
      snapshot_source: "recorded session_context Tool calls"
    }

    messages = Repo.all(from(m in Message, where: m.session_id == ^session.id, order_by: m.id))

    if messages == [] do
      if events == [],
        do: Mix.raise("MCP sessions require --transcript or a nonempty --transcript-dir")

      Export.build(session, context, events, calls, verdicts)
    else
      Export.build_in_app(session, context, messages, calls, verdicts)
    end
  end

  defp write_records(path, records) do
    case File.open(path, [:write, :exclusive, :utf8]) do
      {:ok, file} ->
        try do
          Enum.each(records, fn record ->
            :ok = IO.write(file, [Jason.encode!(record), "\n"])
          end)
        after
          File.close(file)
        end

      {:error, reason} ->
        Mix.raise("Cannot create export #{path}: #{:file.format_error(reason)}")
    end
  end
end
