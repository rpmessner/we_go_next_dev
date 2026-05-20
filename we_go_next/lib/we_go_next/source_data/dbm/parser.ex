defmodule WeGoNext.SourceData.DBM.Parser do
  @moduledoc """
  Extracts static mechanic evidence from DBM Lua modules.

  This parser intentionally handles a focused Lua declaration subset instead of
  evaluating Lua. It tokenizes source, extracts balanced method-call forms, and
  reads only the DBM declarations needed for source-data candidates:

  * `DBM:NewMod`
  * `mod:SetRevision`
  * `mod:SetEncounterID`
  * `mod:SetZone`
  * `mod:SetCreatureID`
  * `mod:NewSpecialWarning*`
  * `warning:SetAlert`

  Tree-sitter Lua would give a complete AST, but would add a larger native
  parser dependency for a narrow static extraction surface. A focused Elixir
  tokenizer keeps the boundary explicit and avoids copying/executing DBM code.
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
    source_lines = source_lines(source)
    {tokens, comments_by_line} = tokenize(source)

    calls =
      tokens
      |> extract_calls(source_lines, comments_by_line)
      |> Enum.map(&Map.put(&1, :source_file, source_file))

    metadata =
      calls
      |> Enum.reduce(base_metadata(), &parse_metadata_call/2)
      |> Map.update!(:creature_ids, &Enum.sort(Enum.uniq(&1)))

    alert_tokens_by_var = alert_tokens_by_var(calls)

    warnings =
      calls
      |> Enum.reduce([], fn call, warnings ->
        case parse_warning_call(call, alert_tokens_by_var) do
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

  defp parse_metadata_call(call, metadata) do
    case {call.receiver, call.method} do
      {"DBM", "NewMod"} ->
        metadata
        |> Map.put(:module_id, integer_arg(Enum.at(call.args, 0)))
        |> Map.put(:module_addon, string_arg(Enum.at(call.args, 1)))
        |> Map.put(:module_map_id, integer_arg(Enum.at(call.args, 3)))

      {"mod", "SetRevision"} ->
        Map.put(metadata, :module_revision, string_arg(Enum.at(call.args, 0)))

      {"mod", "SetEncounterID"} ->
        Map.put(metadata, :encounter_id, first_integer(call.args))

      {"mod", "SetZone"} ->
        Map.put(metadata, :zone_id, first_integer(call.args))

      {"mod", "SetCreatureID"} ->
        Map.update!(metadata, :creature_ids, fn existing ->
          existing ++ integers(call.args)
        end)

      _ ->
        metadata
    end
  end

  defp alert_tokens_by_var(calls) do
    Enum.reduce(calls, %{}, fn call, alerts ->
      if call.method == "SetAlert" do
        tokens =
          call.args
          |> string_literals()
          |> Enum.reject(&role_filter?/1)
          |> Enum.map(&String.downcase/1)

        Map.update(alerts, call.receiver, tokens, &Enum.uniq(&1 ++ tokens))
      else
        alerts
      end
    end)
  end

  defp parse_warning_call(call, alert_tokens_by_var) do
    if call.receiver == "mod" and String.starts_with?(call.method, "NewSpecialWarning") and
         not is_nil(call.assignment_var) do
      label_tokens = common_label_tokens(call.args)
      alert_tokens = Map.get(alert_tokens_by_var, call.assignment_var, [])

      warning =
        %{
          warning_var: call.assignment_var,
          warning_constructor: call.method,
          spell_id: integer_arg(Enum.at(call.args, 0)),
          role_filter: role_filter_from_args(call.args),
          label_tokens: label_tokens,
          alert_tokens: alert_tokens,
          source_file: call.source_file,
          source_line: call.source_line,
          source_line_text: call.source_line_text,
          raw_args: call.raw_args,
          comment: empty_to_nil(call.comment)
        }

      Map.merge(warning, infer_mechanic(warning))
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

  defp extract_calls(tokens, source_lines, comments_by_line) do
    tokens
    |> Enum.with_index()
    |> Enum.reduce([], fn {_token, index}, calls ->
      case extract_call(tokens, index, source_lines, comments_by_line) do
        nil -> calls
        call -> [call | calls]
      end
    end)
    |> Enum.reverse()
  end

  defp extract_call(tokens, index, source_lines, comments_by_line) do
    with %{type: :identifier, value: receiver} = receiver_token <- Enum.at(tokens, index),
         %{type: :symbol, value: ":"} <- Enum.at(tokens, index + 1),
         %{type: :identifier, value: method} <- Enum.at(tokens, index + 2),
         %{type: :symbol, value: "("} <- Enum.at(tokens, index + 3),
         {:ok, arg_tokens} <- call_arg_tokens(tokens, index + 4) do
      args = split_args(arg_tokens)

      %{
        receiver: receiver,
        method: method,
        assignment_var: assignment_var(tokens, index),
        args: args,
        raw_args: source_slice(arg_tokens, source_lines),
        source_line: receiver_token.line,
        source_line_text: Map.get(source_lines, receiver_token.line, ""),
        comment: Map.get(comments_by_line, receiver_token.line)
      }
    else
      _ -> nil
    end
  end

  defp call_arg_tokens(tokens, index), do: call_arg_tokens(tokens, index, 1, [])

  defp call_arg_tokens(_tokens, _index, 0, args), do: {:ok, Enum.reverse(args)}
  defp call_arg_tokens(tokens, index, _depth, _args) when index >= length(tokens), do: :error

  defp call_arg_tokens(tokens, index, depth, args) do
    token = Enum.at(tokens, index)

    cond do
      token.type == :symbol and token.value == "(" ->
        call_arg_tokens(tokens, index + 1, depth + 1, [token | args])

      token.type == :symbol and token.value == ")" and depth == 1 ->
        {:ok, Enum.reverse(args)}

      token.type == :symbol and token.value == ")" ->
        call_arg_tokens(tokens, index + 1, depth - 1, [token | args])

      true ->
        call_arg_tokens(tokens, index + 1, depth, [token | args])
    end
  end

  defp split_args([]), do: []

  defp split_args(tokens) do
    tokens
    |> Enum.reduce(%{args: [], current: [], paren: 0, brace: 0, bracket: 0}, fn token, state ->
      cond do
        top_level_comma?(token, state) ->
          %{state | args: [Enum.reverse(state.current) | state.args], current: []}

        token.type == :symbol and token.value == "(" ->
          push_arg_token(token, %{state | paren: state.paren + 1})

        token.type == :symbol and token.value == ")" ->
          push_arg_token(token, %{state | paren: max(state.paren - 1, 0)})

        token.type == :symbol and token.value == "{" ->
          push_arg_token(token, %{state | brace: state.brace + 1})

        token.type == :symbol and token.value == "}" ->
          push_arg_token(token, %{state | brace: max(state.brace - 1, 0)})

        token.type == :symbol and token.value == "[" ->
          push_arg_token(token, %{state | bracket: state.bracket + 1})

        token.type == :symbol and token.value == "]" ->
          push_arg_token(token, %{state | bracket: max(state.bracket - 1, 0)})

        true ->
          push_arg_token(token, state)
      end
    end)
    |> finish_args()
  end

  defp top_level_comma?(token, state) do
    token.type == :symbol and token.value == "," and state.paren == 0 and state.brace == 0 and
      state.bracket == 0
  end

  defp push_arg_token(token, state), do: %{state | current: [token | state.current]}

  defp finish_args(%{args: args, current: current}) do
    [Enum.reverse(current) | args]
    |> Enum.reverse()
    |> Enum.map(&Enum.reject(&1, fn token -> token.type == :whitespace end))
    |> Enum.reject(&(&1 == []))
  end

  defp assignment_var(tokens, call_index) do
    call_line = Enum.at(tokens, call_index).line

    same_line_before_call =
      tokens
      |> Enum.take(call_index)
      |> Enum.filter(&(&1.line == call_line))

    equals_index =
      same_line_before_call
      |> Enum.with_index()
      |> Enum.filter(fn {token, _index} -> token.type == :symbol and token.value == "=" end)
      |> List.last()
      |> case do
        {_token, index} -> index
        nil -> nil
      end

    if equals_index do
      same_line_before_call
      |> Enum.take(equals_index)
      |> Enum.reverse()
      |> Enum.find(&(&1.type == :identifier and &1.value != "local"))
      |> case do
        nil -> nil
        token -> token.value
      end
    end
  end

  defp source_slice([], _source_lines), do: ""

  defp source_slice(tokens, source_lines) do
    first = List.first(tokens)
    last = List.last(tokens)

    if first.line == last.line do
      source_lines
      |> Map.get(first.line, "")
      |> String.slice(
        first.column - 1,
        last.column + String.length(last.raw) - first.column
      )
      |> String.trim()
    else
      tokens
      |> Enum.map(& &1.raw)
      |> Enum.join(" ")
    end
  end

  defp role_filter_from_args(args) do
    args
    |> string_literals()
    |> Enum.find(&role_filter?/1)
  end

  defp role_filter?(value) do
    Enum.any?(@role_filters, &String.contains?(value, &1))
  end

  defp role_includes?(nil, _role), do: false
  defp role_includes?(role_filter, role), do: String.contains?(role_filter, role)

  defp common_label_tokens(args) do
    args
    |> List.flatten()
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.flat_map(fn
      [
        %{type: :identifier, value: "DBM_COMMON_L"},
        %{type: :symbol, value: "."},
        %{type: :identifier, value: label}
      ] ->
        [label]

      _ ->
        []
    end)
    |> Enum.uniq()
  end

  defp string_arg(nil), do: nil

  defp string_arg(tokens) do
    tokens
    |> Enum.find(&(&1.type == :string))
    |> case do
      nil -> nil
      token -> token.value
    end
  end

  defp string_literals(args) do
    args
    |> List.flatten()
    |> Enum.filter(&(&1.type == :string))
    |> Enum.map(& &1.value)
  end

  defp integer_arg(nil), do: nil

  defp integer_arg(tokens) do
    tokens
    |> Enum.find(&(&1.type == :number))
    |> case do
      nil -> nil
      token -> token.value
    end
  end

  defp first_integer(args) do
    args
    |> integers()
    |> List.first()
  end

  defp integers(args) do
    args
    |> List.flatten()
    |> Enum.filter(&(&1.type == :number))
    |> Enum.map(& &1.value)
  end

  defp intersects?(tokens, candidates) do
    Enum.any?(candidates, &MapSet.member?(tokens, &1))
  end

  defp source_lines(source) do
    source
    |> String.split("\n", trim: false)
    |> Enum.with_index(1)
    |> Map.new(fn {line, line_number} ->
      {line_number, String.trim_trailing(line)}
    end)
  end

  defp tokenize(source) do
    source
    |> do_tokenize(%{line: 1, column: 1, tokens: [], comments: %{}})
    |> then(fn state ->
      {Enum.reverse(state.tokens), state.comments}
    end)
  end

  defp do_tokenize(<<>>, state), do: state

  defp do_tokenize(<<"\r\n", rest::binary>>, state) do
    do_tokenize(rest, %{state | line: state.line + 1, column: 1})
  end

  defp do_tokenize(<<"\n", rest::binary>>, state) do
    do_tokenize(rest, %{state | line: state.line + 1, column: 1})
  end

  defp do_tokenize(<<"\r", rest::binary>>, state) do
    do_tokenize(rest, %{state | column: state.column + 1})
  end

  defp do_tokenize(<<"--[[", rest::binary>>, state) do
    {remaining, line, column} = skip_long_comment(rest, state.line, state.column + 4)
    do_tokenize(remaining, %{state | line: line, column: column})
  end

  defp do_tokenize(<<"--", rest::binary>>, state) do
    {comment, remaining} = take_until_newline(rest, "")
    comments = Map.put_new(state.comments, state.line, String.trim(comment))

    do_tokenize(remaining, %{
      state
      | comments: comments,
        column: state.column + 2 + byte_size(comment)
    })
  end

  defp do_tokenize(<<char::utf8, rest::binary>>, state) when char in [?\s, ?\t, ?\f, ?\v] do
    do_tokenize(rest, %{state | column: state.column + 1})
  end

  defp do_tokenize(<<quote::utf8, rest::binary>>, state) when quote in [?\", ?'] do
    {value, raw_tail, remaining, line, column} =
      take_string(rest, quote, "", <<quote::utf8>>, state.line, state.column + 1)

    token = token(:string, value, raw_tail, state.line, state.column)
    do_tokenize(remaining, push_token(state, token, line, column))
  end

  defp do_tokenize(<<char::utf8, _rest::binary>> = source, state) when char in ?0..?9 do
    {raw, remaining} = take_while(source, "", &digit?/1)
    token = token(:number, String.to_integer(raw), raw, state.line, state.column)

    do_tokenize(
      remaining,
      push_token(state, token, state.line, state.column + String.length(raw))
    )
  end

  defp do_tokenize(<<char::utf8, _rest::binary>> = source, state) do
    cond do
      identifier_start?(char) ->
        {raw, remaining} = take_while(source, "", &identifier_continue?/1)
        token = token(:identifier, raw, raw, state.line, state.column)

        do_tokenize(
          remaining,
          push_token(state, token, state.line, state.column + String.length(raw))
        )

      symbol?(char) ->
        raw = <<char::utf8>>
        token = token(:symbol, raw, raw, state.line, state.column)
        <<_::utf8, remaining::binary>> = source
        do_tokenize(remaining, push_token(state, token, state.line, state.column + 1))

      true ->
        <<_::utf8, remaining::binary>> = source
        do_tokenize(remaining, %{state | column: state.column + 1})
    end
  end

  defp token(type, value, raw, line, column) do
    %{
      type: type,
      value: value,
      raw: raw,
      line: line,
      column: column
    }
  end

  defp push_token(state, token, line, column) do
    %{state | tokens: [token | state.tokens], line: line, column: column}
  end

  defp take_string(<<>>, _quote, value, raw, line, column), do: {value, raw, "", line, column}

  defp take_string(<<"\\", escaped::utf8, rest::binary>>, quote, value, raw, line, column) do
    take_string(
      rest,
      quote,
      value <> <<escaped::utf8>>,
      raw <> "\\" <> <<escaped::utf8>>,
      line,
      column + 2
    )
  end

  defp take_string(<<quote::utf8, rest::binary>>, quote, value, raw, line, column) do
    {value, raw <> <<quote::utf8>>, rest, line, column + 1}
  end

  defp take_string(<<"\r\n", rest::binary>>, quote, value, raw, line, _column) do
    take_string(rest, quote, value <> "\n", raw <> "\r\n", line + 1, 1)
  end

  defp take_string(<<"\n", rest::binary>>, quote, value, raw, line, _column) do
    take_string(rest, quote, value <> "\n", raw <> "\n", line + 1, 1)
  end

  defp take_string(<<char::utf8, rest::binary>>, quote, value, raw, line, column) do
    take_string(rest, quote, value <> <<char::utf8>>, raw <> <<char::utf8>>, line, column + 1)
  end

  defp take_until_newline(<<>>, comment), do: {comment, ""}
  defp take_until_newline(<<"\n", _rest::binary>> = remaining, comment), do: {comment, remaining}

  defp take_until_newline(<<"\r\n", _rest::binary>> = remaining, comment),
    do: {comment, remaining}

  defp take_until_newline(<<char::utf8, rest::binary>>, comment) do
    take_until_newline(rest, comment <> <<char::utf8>>)
  end

  defp skip_long_comment(<<>>, line, column), do: {"", line, column}

  defp skip_long_comment(<<"]]", rest::binary>>, line, column) do
    {rest, line, column + 2}
  end

  defp skip_long_comment(<<"\r\n", rest::binary>>, line, _column) do
    skip_long_comment(rest, line + 1, 1)
  end

  defp skip_long_comment(<<"\n", rest::binary>>, line, _column) do
    skip_long_comment(rest, line + 1, 1)
  end

  defp skip_long_comment(<<_char::utf8, rest::binary>>, line, column) do
    skip_long_comment(rest, line, column + 1)
  end

  defp take_while(<<>>, acc, _predicate), do: {acc, ""}

  defp take_while(<<char::utf8, rest::binary>>, acc, predicate) do
    if predicate.(char) do
      take_while(rest, acc <> <<char::utf8>>, predicate)
    else
      {acc, <<char::utf8, rest::binary>>}
    end
  end

  defp identifier_start?(char), do: char in ?a..?z or char in ?A..?Z or char == ?_
  defp identifier_continue?(char), do: identifier_start?(char) or digit?(char)
  defp digit?(char), do: char in ?0..?9

  defp symbol?(char) do
    char in [?(, ?), ?{, ?}, ?[, ?], ?,, ?:, ?., ?=, ?;]
  end

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
