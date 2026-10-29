defmodule WeGoNext.Analysis.Playbooks do
  @moduledoc "Versioned Markdown Playbooks. Front matter uses scalar strings and JSON arrays."
  @families ~w(wipes deaths mechanics coaching own-play)

  def directory, do: :we_go_next |> :code.priv_dir() |> Path.join("analysis/playbooks")

  def parse(id, text) do
    with ["", header, body] <- String.split(text, ~r/^---\r?\n/m, parts: 3),
         {:ok, fields} <- fields(header),
         true <- valid?(fields) do
      {:ok, Map.merge(fields, %{id: id, body: body})}
    else
      _ -> {:error, "Invalid Playbook #{id}"}
    end
  end

  def select(books, encounter_ids) do
    Enum.filter(books, fn book ->
      book.status == "active" and
        (book.scope == "global" or Enum.any?(book.encounter_ids, &(&1 in encounter_ids)))
    end)
  end

  def for_boss(books, boss, pulls) do
    ids =
      pulls
      |> Enum.filter(&(is_binary(boss) and boss in [&1.boss, &1.boss_id]))
      |> Enum.map(& &1.boss_id)
      |> then(&[boss | &1])
      |> Enum.flat_map(fn value ->
        case Integer.parse(to_string(value)) do
          {id, ""} -> [id]
          _ -> []
        end
      end)

    select(books, ids)
  end

  def load do
    directory()
    |> Path.join("*.md")
    |> Path.wildcard()
    |> Enum.map(fn path ->
      id = Path.basename(path, ".md")
      {:ok, book} = parse(id, File.read!(path))
      Map.put(book, :git_commit, git_commit(path))
    end)
  end

  def provenance(book), do: Map.take(book, [:id, :git_commit])
  def metadata(book), do: Map.drop(book, [:body])

  def git_commit(path) do
    case System.cmd("git", ["-C", Path.dirname(path), "rev-parse", "HEAD"],
           stderr_to_stdout: true
         ) do
      {commit, 0} -> String.trim(commit)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp fields(header) do
    header
    |> String.split("\n", trim: true)
    |> Enum.reduce_while({:ok, %{}}, &field/2)
    |> decode_fields()
  end

  defp field(line, {:ok, acc}) do
    case String.split(line, ":", parts: 2) do
      [key, value] when key in ~w(title scope encounter_ids question_families status) ->
        if Map.has_key?(acc, key),
          do: {:halt, :error},
          else: {:cont, {:ok, Map.put(acc, key, String.trim(value))}}

      _ ->
        {:halt, :error}
    end
  end

  defp decode_fields({:ok, fields}) when map_size(fields) == 5 do
    with {:ok, ids} <- Jason.decode(fields["encounter_ids"]),
         {:ok, families} <- Jason.decode(fields["question_families"]) do
      {:ok,
       %{
         title: fields["title"],
         scope: fields["scope"],
         encounter_ids: ids,
         question_families: families,
         status: fields["status"]
       }}
    end
  end

  defp decode_fields(_), do: :error

  defp valid?(book) do
    book.title != "" and book.scope in ~w(global boss) and book.status in ~w(active retired) and
      valid_ids?(book) and valid_families?(book.question_families)
  end

  defp valid_ids?(book) do
    is_list(book.encounter_ids) and Enum.all?(book.encounter_ids, &(is_integer(&1) and &1 > 0)) and
      (book.scope != "boss" or book.encounter_ids != [])
  end

  defp valid_families?(families),
    do: is_list(families) and Enum.all?(families, &(&1 in @families))
end
