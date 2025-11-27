defmodule WeGoNext.LogReader do
  @moduledoc """
  Reads and parses WoW combat log files.
  """

  alias WeGoNext.Encounter

  @doc """
  Parses a combat log file and extracts all encounters.
  """
  def parse_file(path) do
    path
    |> File.stream!()
    |> Stream.map(&parse_line/1)
    |> Enum.reduce(%{encounters: [], current: nil}, &process_event/2)
    |> Map.get(:encounters)
    |> Enum.reverse()
  end

  @doc """
  Parses a combat log file starting from a byte offset.
  Returns {encounters_with_metadata, end_byte} where encounters_with_metadata
  is a list of {encounter, raw_lines, start_byte, end_byte} tuples.
  """
  def parse_file_with_bytes(path, start_byte \\ 0) do
    file = File.open!(path, [:read, :binary])

    try do
      # Seek to start position
      if start_byte > 0 do
        :file.position(file, start_byte)
      end

      {encounters, current_byte} = read_and_parse(file, start_byte)
      {encounters, current_byte}
    after
      File.close(file)
    end
  end

  defp read_and_parse(file, start_byte) do
    state = %{
      encounters: [],
      current: nil,
      current_lines: [],
      current_start_byte: nil,
      byte_offset: start_byte
    }

    do_read_and_parse(file, state)
  end

  defp do_read_and_parse(file, state) do
    case IO.read(file, :line) do
      :eof ->
        {Enum.reverse(state.encounters), state.byte_offset}

      {:error, _reason} ->
        {Enum.reverse(state.encounters), state.byte_offset}

      line ->
        line_bytes = byte_size(line)
        new_byte_offset = state.byte_offset + line_bytes

        parsed = parse_line(line)
        new_state = process_event_with_bytes(parsed, line, state, new_byte_offset)

        do_read_and_parse(file, %{new_state | byte_offset: new_byte_offset})
    end
  end

  defp process_event_with_bytes({:invalid, _, _}, _line, state, _byte_offset), do: state

  defp process_event_with_bytes({timestamp, "ENCOUNTER_START", fields}, line, state, _byte_offset) do
    encounter = Encounter.start(fields, timestamp)

    %{state |
      current: encounter,
      current_lines: [line],
      current_start_byte: state.byte_offset
    }
  end

  defp process_event_with_bytes({_timestamp, "ENCOUNTER_END", _fields}, _line, %{current: nil} = state, _byte_offset) do
    state
  end

  defp process_event_with_bytes({timestamp, "ENCOUNTER_END", fields}, line, state, byte_offset) do
    completed_encounter = Encounter.finish(state.current, fields, timestamp)
    raw_lines = Enum.reverse([line | state.current_lines])

    encounter_tuple = {
      completed_encounter,
      raw_lines,
      state.current_start_byte,
      byte_offset
    }

    %{state |
      encounters: [encounter_tuple | state.encounters],
      current: nil,
      current_lines: [],
      current_start_byte: nil
    }
  end

  defp process_event_with_bytes({_timestamp, _event_type, _fields}, _line, %{current: nil} = state, _byte_offset) do
    state
  end

  defp process_event_with_bytes({timestamp, event_type, fields}, line, state, _byte_offset) do
    event = %{timestamp: timestamp, type: event_type, data: fields}
    updated_encounter = Encounter.add_event(state.current, event)

    %{state |
      current: updated_encounter,
      current_lines: [line | state.current_lines]
    }
  end

  @doc """
  Parses a single combat log line into {timestamp, event_type, fields}.
  """
  def parse_line(line) do
    case String.split(line, "  ", parts: 2) do
      [timestamp_str, event_data] ->
        timestamp = parse_timestamp(timestamp_str)
        fields = parse_csv(String.trim(event_data))
        event_type = List.first(fields)

        {timestamp, event_type, fields}

      _ ->
        {:invalid, nil, []}
    end
  end

  # Processes each event and accumulates encounters
  defp process_event({:invalid, _, _}, acc), do: acc

  defp process_event({timestamp, "ENCOUNTER_START", fields}, acc) do
    encounter = Encounter.start(fields, timestamp)
    %{acc | current: encounter}
  end

  defp process_event({_timestamp, "ENCOUNTER_END", _fields}, %{current: nil} = acc) do
    # Ignore ENCOUNTER_END without a start
    acc
  end

  defp process_event({timestamp, "ENCOUNTER_END", fields}, %{current: current} = acc) do
    completed_encounter = Encounter.finish(current, fields, timestamp)
    %{acc | encounters: [completed_encounter | acc.encounters], current: nil}
  end

  defp process_event({_timestamp, _event_type, _fields}, %{current: nil} = acc) do
    # Not in an encounter, ignore event
    acc
  end

  defp process_event({timestamp, event_type, fields}, %{current: current} = acc) do
    event = %{timestamp: timestamp, type: event_type, data: fields}
    updated_encounter = Encounter.add_event(current, event)
    %{acc | current: updated_encounter}
  end

  # Parse WoW combat log timestamp format: "11/22/2025 11:39:35.297-5"
  defp parse_timestamp(timestamp_str) do
    # Remove timezone offset
    [datetime_part | _] = String.split(timestamp_str, "-")

    case String.split(datetime_part, " ") do
      [date_part, time_part] ->
        [month, day, year] = String.split(date_part, "/")
        [time_str, ms_str] = String.split(time_part, ".")
        [hour, minute, second] = String.split(time_str, ":")

        # Create a NaiveDateTime
        {:ok, datetime} = NaiveDateTime.new(
          String.to_integer(year),
          String.to_integer(month),
          String.to_integer(day),
          String.to_integer(hour),
          String.to_integer(minute),
          String.to_integer(second),
          String.to_integer(ms_str) * 1000  # Convert milliseconds to microseconds
        )

        datetime

      _ ->
        nil
    end
  end

  # Parse CSV-style comma-separated fields, respecting quoted strings
  defp parse_csv(line) do
    line
    |> String.split(~r/,(?=(?:[^"]*"[^"]*")*[^"]*$)/)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.trim(&1, "\""))
  end
end
