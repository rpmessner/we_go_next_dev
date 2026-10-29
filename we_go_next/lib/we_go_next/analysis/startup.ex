defmodule WeGoNext.Analysis.Startup do
  @moduledoc "Shared prompt and Tool startup: normalize intent, resolve imported logs, and explain choices."
  import Ecto.Query
  alias WeGoNext.{CombatLogFile, Repo}
  alias WeGoNext.Analysis.{Playbooks, ReadModel, Session}
  alias WeGoNext.Encounters.Encounter

  def start(args) do
    logs = imported_logs()

    with {:ok, args} <- normalize(args),
         {:ok, log} <- resolve_log(args["log"], logs) do
      pulls = ReadModel.pulls(%{combat_log_file_id: log.id})
      boss = resolve_boss(args["boss"], pulls)
      books = Playbooks.for_boss(Playbooks.load(), boss, pulls)

      Repo.insert(%Session{
        started_at: DateTime.utc_now(),
        combat_log_file_id: log.id,
        boss: boss,
        loaded_playbooks: Enum.map(books, &Playbooks.provenance/1),
        playbooks: books
      })
    else
      {:error, reason} -> {:error, choices(reason, logs)}
    end
  end

  def response(args) do
    case start(args) do
      {:ok, session} ->
        {:ok, normalized} = normalize(args)

        warning =
          if normalized["boss"] && is_nil(session.boss),
            do:
              "Unknown boss #{inspect(normalized["boss"])} in this log; started with boss unset.\n",
            else: ""

        %{session_id: session.id, instructions: warning <> instructions(session)}

      {:error, reason} ->
        %{session_id: nil, instructions: reason}
    end
  end

  defp instructions(session) do
    analyst = :we_go_next |> :code.priv_dir() |> Path.join("analysis/analyst.md") |> File.read!()

    analyst <>
      "\nAnalysis session id: #{session.id}\nLog id: #{session.combat_log_file_id}\nTarget boss: #{session.boss || "all"}\n" <>
      Enum.map_join(session.playbooks, "\n", fn book ->
        "\nPlaybook: #{book.id} (git #{book.git_commit || "unknown"})\n#{book.body}"
      end)
  end

  defp normalize(args) when is_map(args) do
    if Enum.all?(args, fn {key, value} -> key in ~w(boss log) and is_binary(value) end) do
      {:ok, Map.new(args, fn {key, value} -> {key, blank_to_nil(value)} end)}
    else
      {:error,
       "Arguments must be strings: boss (optional name/id), log (optional id/filename fragment)."}
    end
  end

  defp normalize(_),
    do: {:error, "Arguments must be an object with optional boss and log strings."}

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp resolve_log(nil, [latest | _]), do: {:ok, latest}
  defp resolve_log(nil, []), do: {:error, "No imported logs are available."}

  defp resolve_log(value, logs) do
    by_id =
      case Integer.parse(value) do
        {id, ""} -> Enum.filter(logs, &(&1.id == id))
        _ -> []
      end

    matches =
      if by_id == [],
        do:
          Enum.filter(
            logs,
            &String.contains?(
              String.downcase(Path.basename(&1.file_path)),
              String.downcase(value)
            )
          ),
        else: by_id

    case matches do
      [log] -> {:ok, log}
      [] -> {:error, "Unknown imported log #{inspect(value)}."}
      _ -> {:error, "Ambiguous log #{inspect(value)}; more than one imported filename matches."}
    end
  end

  defp resolve_boss(nil, _pulls), do: nil

  defp resolve_boss(boss, pulls) do
    case Enum.find(
           pulls,
           &(boss == &1.boss_id or String.downcase(boss) == String.downcase(&1.boss))
         ) do
      nil -> nil
      pull -> pull.boss
    end
  end

  defp imported_logs do
    Repo.all(
      from(l in CombatLogFile,
        left_join: e in Encounter,
        on: e.combat_log_file_id == l.id,
        where: not is_nil(l.last_parsed_at),
        group_by: l.id,
        order_by: [desc: l.last_parsed_at, desc: l.id],
        select: %{
          id: l.id,
          file_path: l.file_path,
          last_parsed_at: l.last_parsed_at,
          encounter_count: count(e.id)
        }
      )
    )
  end

  defp choices(reason, logs) do
    rows =
      Enum.map_join(Enum.take(logs, 5), "\n", fn log ->
        "- #{log.id}: #{Path.basename(log.file_path)} | #{DateTime.to_iso8601(log.last_parsed_at)} | #{log.encounter_count} encounters"
      end)

    "No Analysis session started. #{reason}\nRecent imported logs (date = last import, UTC):\n#{rows}\n" <>
      "Choose one with log: <id> or a unique filename fragment; omit log for the latest import. boss is the first prompt argument, log is second."
  end
end
