defmodule WeGoNext.SourceData.WowAnalyzer.Parser do
  @moduledoc """
  Extracts static timeline evidence from WowAnalyzer raid boss declarations.

  This parser intentionally reads the TypeScript source as text. It does not
  evaluate or reuse WowAnalyzer runtime code. The extracted rows are source
  evidence for later review, not active rules.
  """

  @type parsed_file :: %{
          encounter_id: integer() | nil,
          encounter_name: String.t() | nil,
          timeline_entries: [map()]
        }

  @doc """
  Parses a WowAnalyzer TypeScript boss file.
  """
  @spec parse_file(Path.t()) :: {:ok, parsed_file()} | {:error, term()}
  def parse_file(path) when is_binary(path) do
    case File.read(path) do
      {:ok, body} -> parse_string(body, source_file: path)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Parses WowAnalyzer boss source.
  """
  @spec parse_string(String.t(), keyword()) :: {:ok, parsed_file()}
  def parse_string(source, opts \\ []) when is_binary(source) do
    source_file = Keyword.get(opts, :source_file, "inline")

    lines =
      source
      |> String.split("\n", trim: false)
      |> Enum.with_index(1)

    {:ok,
     %{
       encounter_id: top_level_id(source),
       encounter_name: top_level_name(source),
       timeline_entries: parse_timeline_entries(lines, source_file)
     }}
  end

  defp top_level_id(source) do
    case Regex.run(~r/(?:^|\n)\s*id:\s*(\d+)\s*,/, source, capture: :all_but_first) do
      [id] -> parse_integer(id)
      _ -> nil
    end
  end

  defp top_level_name(source) do
    case Regex.run(~r/(?:^|\n)\s*name:\s*'([^']*)'\s*,/, source, capture: :all_but_first) do
      [name] ->
        name

      _ ->
        case Regex.run(~r/(?:^|\n)\s*name:\s*"([^"]*)"\s*,/, source, capture: :all_but_first) do
          [name] -> name
          _ -> nil
        end
    end
  end

  defp parse_timeline_entries(lines, source_file) do
    lines
    |> Enum.reduce(%{section: nil, comment: nil, entries: []}, fn {line, line_number}, acc ->
      {code, comment} = split_comment(line)

      cond do
        timeline_section?(code, "abilities") ->
          %{acc | section: "ability", comment: empty_to_nil(comment)}

        timeline_section?(code, "debuffs") ->
          %{acc | section: "debuff", comment: empty_to_nil(comment)}

        acc.section && section_end?(code) ->
          %{acc | section: nil, comment: nil}

        acc.section && comment_only?(code, comment) ->
          %{acc | comment: empty_to_nil(comment)}

        acc.section ->
          parse_entry_line(code, acc.section)
          |> case do
            nil ->
              acc

            entry ->
              entry =
                entry
                |> Map.put(:comment, empty_to_nil(comment) || acc.comment)
                |> Map.put(:source_file, source_file)
                |> Map.put(:source_line, line_number)
                |> Map.put(:source_line_text, String.trim_trailing(line))
                |> infer_mechanic()

              %{acc | entries: [entry | acc.entries]}
          end

        true ->
          acc
      end
    end)
    |> Map.fetch!(:entries)
    |> Enum.reverse()
  end

  defp timeline_section?(code, name) do
    Regex.match?(~r/\b#{name}\s*:\s*\[/, code)
  end

  defp section_end?(code) do
    code
    |> String.trim()
    |> String.starts_with?("]")
  end

  defp comment_only?(code, comment) do
    String.trim(code) == "" && not is_nil(empty_to_nil(comment))
  end

  defp parse_entry_line(code, timeline_type) do
    with [object_body] <- Regex.run(~r/\{(?<body>[^}]*)\}/, code, capture: ["body"]),
         id when is_integer(id) <- property_integer(object_body, "id") do
      event_type =
        property_string(object_body, "type") ||
          if(timeline_type == "debuff", do: "debuff", else: nil)

      raw_entry =
        %{
          "id" => id,
          "type" => event_type,
          "bossOnly" => property_boolean(object_body, "bossOnly")
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      %{
        timeline_type: timeline_type,
        event_type: event_type,
        spell_id: id,
        boss_only: property_boolean(object_body, "bossOnly"),
        raw_entry: raw_entry
      }
    else
      _ -> nil
    end
  end

  defp infer_mechanic(entry) do
    text =
      [
        entry.comment,
        entry.event_type,
        entry.timeline_type
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    inferred =
      cond do
        contains_any?(text, ["interrupt", "interrupting"]) ->
          inferred("interrupt", "high", ["comment:interrupt"])

        contains_any?(text, ["kick", "kicks"]) ->
          inferred("interrupt", "medium", ["comment:kick"])

        contains_any?(text, ["dispel", "cleanse"]) ->
          inferred("healer_mechanic", "high", ["comment:dispel"])

        contains_any?(text, ["group soak", "soak"]) ->
          inferred("soak", "high", ["comment:soak"])

        contains_any?(text, ["tank", "taunt"]) ->
          inferred("tank_mechanic", "high", ["comment:tank"])

        contains_any?(text, ["spread", "spreads"]) ->
          inferred("spread", "medium", ["comment:spread"])

        contains_any?(text, ["stack", "stacks"]) ->
          inferred("stack", "medium", ["comment:stack"])

        contains_any?(text, [
          "area denial",
          "avoid",
          "beam",
          "breath",
          "cone",
          "cones",
          "dive",
          "dives",
          "dodge",
          "frontal",
          "puddle",
          "puddles",
          "spinny"
        ]) ->
          inferred("avoidable", "medium", ["comment:movement"])

        true ->
          inferred(nil, "low", [])
      end

    Map.merge(entry, inferred)
  end

  defp inferred(mechanic_type, confidence, tags) do
    %{
      inferred_mechanic_type: mechanic_type,
      confidence: confidence,
      inference_tags: tags
    }
  end

  defp contains_any?(text, fragments) do
    Enum.any?(fragments, &String.contains?(text, &1))
  end

  defp split_comment(line) do
    case :binary.match(line, "//") do
      {index, _length} ->
        code = binary_part(line, 0, index)
        comment = binary_part(line, index + 2, byte_size(line) - index - 2)
        {code, String.trim(comment)}

      :nomatch ->
        {line, nil}
    end
  end

  defp property_integer(body, property) do
    regex = Regex.compile!("\\b#{property}\\s*:\\s*(\\d+)\\b")

    case Regex.run(regex, body, capture: :all_but_first) do
      [value] -> parse_integer(value)
      _ -> nil
    end
  end

  defp property_string(body, property) do
    regex = Regex.compile!("\\b#{property}\\s*:\\s*'([^']*)'")

    case Regex.run(regex, body, capture: :all_but_first) do
      [value] ->
        value

      _ ->
        regex = Regex.compile!("\\b#{property}\\s*:\\s*\"([^\"]*)\"")

        case Regex.run(regex, body, capture: :all_but_first) do
          [value] -> value
          _ -> nil
        end
    end
  end

  defp property_boolean(body, property) do
    regex = Regex.compile!("\\b#{property}\\s*:\\s*(true|false)\\b")

    case Regex.run(regex, body, capture: :all_but_first) do
      ["true"] -> true
      ["false"] -> false
      _ -> nil
    end
  end

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil

  defp empty_to_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end
end
