defmodule WeGoNext.SourceData.DBM.Parser do
  @moduledoc """
  Extracts static mechanic evidence from DBM Lua modules.

  This parser intentionally handles the regular DBM declaration shape rather
  than evaluating Lua. It extracts the source facts we need for inferred
  mechanic candidates: encounter/module identity, warning constructors, spell
  ids, role filters, DBM common labels, alert voice tokens, comments, and
  file/line provenance.
  """

  @role_filters ~w(HasInterrupt MagicDispeller Tank Healer MeleeDps RangedDps Dps)
  @movement_alert_tokens ~w(watchstep watchfeet justrun frontal dodgebreath chargemove moveaway runout)
  @spread_alert_tokens ~w(scatter spread)
  @soak_alert_tokens ~w(gathershare soakincoming soakline soakshared)
  @healer_alert_tokens ~w(dispelboss dispelnow absorbyou healabsorb)

  @type parsed_module :: %{
          module_id: integer() | nil,
          module_addon: String.t() | nil,
          module_map_id: integer() | nil,
          module_revision: String.t() | nil,
          encounter_id: integer() | nil,
          zone_id: integer() | nil,
          creature_ids: [integer()],
          warnings: [map()]
        }

  @doc """
  Parses a DBM Lua file.
  """
  @spec parse_file(Path.t()) :: {:ok, parsed_module()} | {:error, term()}
  def parse_file(path) when is_binary(path) do
    case File.read(path) do
      {:ok, body} -> parse_string(body, source_file: path)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Parses DBM Lua module source.
  """
  @spec parse_string(String.t(), keyword()) :: {:ok, parsed_module()}
  def parse_string(source, opts \\ []) when is_binary(source) do
    source_file = Keyword.get(opts, :source_file, "inline")

    lines =
      source
      |> String.split("\n", trim: false)
      |> Enum.with_index(1)

    metadata = Enum.reduce(lines, base_metadata(), &parse_metadata_line/2)
    alert_tokens_by_var = alert_tokens_by_var(lines)

    warnings =
      lines
      |> Enum.reduce([], fn {line, line_number}, warnings ->
        case parse_warning_line(line, line_number, source_file, alert_tokens_by_var) do
          nil -> warnings
          warning -> [warning | warnings]
        end
      end)
      |> Enum.reverse()

    {:ok, Map.put(metadata, :warnings, warnings)}
  end

  defp base_metadata do
    %{
      module_id: nil,
      module_addon: nil,
      module_map_id: nil,
      module_revision: nil,
      encounter_id: nil,
      zone_id: nil,
      creature_ids: []
    }
  end

  defp parse_metadata_line({line, _line_number}, metadata) do
    {code, _comment} = split_comment(line)

    cond do
      String.contains?(code, "DBM:NewMod(") ->
        parse_new_mod(code, metadata)

      String.contains?(code, "mod:SetRevision(") ->
        Map.put(metadata, :module_revision, first_string_literal(code))

      String.contains?(code, "mod:SetEncounterID(") ->
        Map.put(metadata, :encounter_id, first_integer(code))

      String.contains?(code, "mod:SetZone(") ->
        Map.put(metadata, :zone_id, first_integer(code))

      String.contains?(code, "mod:SetCreatureID(") ->
        Map.update!(metadata, :creature_ids, fn existing ->
          (existing ++ all_integers(code))
          |> Enum.uniq()
          |> Enum.sort()
        end)

      true ->
        metadata
    end
  end

  defp parse_new_mod(code, metadata) do
    case Regex.run(~r/DBM:NewMod\((?<args>.*)\)/, code, capture: ["args"]) do
      [args_text] ->
        args = split_args(args_text)

        metadata
        |> Map.put(:module_id, parse_integer(Enum.at(args, 0)))
        |> Map.put(:module_addon, parse_string_literal(Enum.at(args, 1)))
        |> Map.put(:module_map_id, parse_integer(Enum.at(args, 3)))

      _ ->
        metadata
    end
  end

  defp alert_tokens_by_var(lines) do
    Enum.reduce(lines, %{}, fn {line, _line_number}, alerts ->
      {code, _comment} = split_comment(line)

      case Regex.run(~r/^\s*(?<var>\w+):SetAlert\((?<args>.*)\)/, code, capture: ["var", "args"]) do
        [var, args_text] ->
          tokens =
            args_text
            |> string_literals()
            |> Enum.reject(&role_filter?/1)
            |> Enum.map(&String.downcase/1)

          Map.update(alerts, var, tokens, &Enum.uniq(&1 ++ tokens))

        _ ->
          alerts
      end
    end)
  end

  defp parse_warning_line(line, line_number, source_file, alert_tokens_by_var) do
    {code, comment} = split_comment(line)

    case Regex.run(
           ~r/^\s*(?:local\s+)?(?<var>\w+)\s*=\s*mod:(?<constructor>NewSpecialWarning\w*)\((?<args>.*)\)/,
           code,
           capture: ["var", "constructor", "args"]
         ) do
      [warning_var, warning_constructor, raw_args] ->
        args = split_args(raw_args)
        label_tokens = common_label_tokens(raw_args)
        alert_tokens = Map.get(alert_tokens_by_var, warning_var, [])

        warning =
          %{
            warning_var: warning_var,
            warning_constructor: warning_constructor,
            spell_id: parse_spell_id(Enum.at(args, 0)),
            role_filter: role_filter_from_args(args),
            label_tokens: label_tokens,
            alert_tokens: alert_tokens,
            source_file: source_file,
            source_line: line_number,
            source_line_text: String.trim_trailing(line),
            raw_args: String.trim(raw_args),
            comment: empty_to_nil(comment)
          }

        Map.merge(warning, infer_mechanic(warning))

      _ ->
        nil
    end
  end

  defp infer_mechanic(warning) do
    constructor = warning.warning_constructor
    labels = MapSet.new(warning.label_tokens)
    alerts = MapSet.new(warning.alert_tokens)
    role_filter = warning.role_filter || ""

    cond do
      String.contains?(constructor, "Interrupt") ->
        inferred("interrupt", "high", ["warning:interrupt"])

      MapSet.member?(labels, "INTERRUPTS") or String.contains?(role_filter, "HasInterrupt") ->
        inferred("interrupt", "medium", ["label:interrupts"])

      String.contains?(constructor, "Soak") ->
        inferred("soak", "high", ["warning:soak"])

      MapSet.member?(labels, "GROUPSOAK") or MapSet.member?(labels, "GROUPSOAKS") or
          intersects?(alerts, @soak_alert_tokens) ->
        inferred("soak", "medium", ["label:group_soak"])

      String.contains?(constructor, "MoveAway") or intersects?(alerts, @spread_alert_tokens) ->
        inferred("spread", "medium", ["alert:spread"])

      String.contains?(constructor, "Dodge") or String.contains?(constructor, "GTFO") or
          String.contains?(constructor, "Move") ->
        inferred("avoidable", "high", ["warning:movement"])

      MapSet.member?(labels, "DODGES") or MapSet.member?(labels, "FRONTAL") or
          intersects?(alerts, @movement_alert_tokens) ->
        inferred("avoidable", "medium", ["label:movement"])

      String.contains?(constructor, "Defensive") or String.contains?(constructor, "Taunt") or
        MapSet.member?(labels, "TANKCOMBO") or role_includes?(role_filter, "Tank") ->
        inferred("tank_mechanic", "medium", ["role:tank"])

      String.contains?(constructor, "Dispel") or role_filter == "MagicDispeller" or
        role_includes?(role_filter, "Healer") or MapSet.member?(labels, "DISPELS") or
        MapSet.member?(labels, "HEALABSORBS") or MapSet.member?(labels, "HEALABSORB") or
          intersects?(alerts, @healer_alert_tokens) ->
        inferred("healer_mechanic", "medium", ["role:healer"])

      true ->
        inferred(nil, "low", [])
    end
  end

  defp inferred(mechanic_type, confidence, tags) do
    %{
      inferred_mechanic_type: mechanic_type,
      confidence: confidence,
      inference_tags: tags
    }
  end

  defp split_comment(line) do
    case :binary.match(line, "--") do
      {index, _length} ->
        code = binary_part(line, 0, index)
        comment = binary_part(line, index + 2, byte_size(line) - index - 2)
        {code, String.trim(comment)}

      :nomatch ->
        {line, nil}
    end
  end

  defp split_args(args_text) when is_binary(args_text) do
    args_text
    |> String.graphemes()
    |> split_args([], "", %{brace_depth: 0, paren_depth: 0, in_string: false})
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp split_args([], args, current, _state), do: Enum.reverse([current | args])

  defp split_args([char | rest], args, current, state) do
    cond do
      char == "\"" ->
        split_args(rest, args, current <> char, %{state | in_string: !state.in_string})

      state.in_string ->
        split_args(rest, args, current <> char, state)

      char == "{" ->
        split_args(rest, args, current <> char, %{state | brace_depth: state.brace_depth + 1})

      char == "}" ->
        split_args(rest, args, current <> char, %{
          state
          | brace_depth: max(state.brace_depth - 1, 0)
        })

      char == "(" ->
        split_args(rest, args, current <> char, %{state | paren_depth: state.paren_depth + 1})

      char == ")" ->
        split_args(rest, args, current <> char, %{
          state
          | paren_depth: max(state.paren_depth - 1, 0)
        })

      char == "," and state.brace_depth == 0 and state.paren_depth == 0 ->
        split_args(rest, [current | args], "", state)

      true ->
        split_args(rest, args, current <> char, state)
    end
  end

  defp role_filter_from_args(args) do
    args
    |> Enum.flat_map(&string_literals/1)
    |> Enum.find(&role_filter?/1)
  end

  defp role_filter?(value) do
    Enum.any?(@role_filters, &String.contains?(value, &1))
  end

  defp role_includes?(nil, _role), do: false
  defp role_includes?(role_filter, role), do: String.contains?(role_filter, role)

  defp common_label_tokens(value) do
    ~r/DBM_COMMON_L\.([A-Z_]+)/
    |> Regex.scan(value, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp string_literals(nil), do: []

  defp string_literals(value) do
    ~r/"([^"]*)"/
    |> Regex.scan(value, capture: :all_but_first)
    |> List.flatten()
  end

  defp first_string_literal(value) do
    value
    |> string_literals()
    |> List.first()
  end

  defp parse_string_literal(nil), do: nil
  defp parse_string_literal(value), do: first_string_literal(value)

  defp first_integer(value) do
    value
    |> all_integers()
    |> List.first()
  end

  defp all_integers(value) when is_binary(value) do
    ~r/\b\d+\b/
    |> Regex.scan(value)
    |> List.flatten()
    |> Enum.map(&String.to_integer/1)
  end

  defp all_integers(_value), do: []

  defp parse_integer(nil), do: nil

  defp parse_integer(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      text -> if String.match?(text, ~r/^\d+$/), do: String.to_integer(text)
    end
  end

  defp parse_spell_id(nil), do: nil
  defp parse_spell_id(value), do: first_integer(value)

  defp intersects?(tokens, candidates) do
    Enum.any?(candidates, &MapSet.member?(tokens, &1))
  end

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
