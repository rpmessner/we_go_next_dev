defmodule WeGoNext.LogReader do
  @moduledoc """
  Reads and parses WoW combat log files.
  """

  alias WeGoNext.Encounter

  # Report progress every ~1% of the file
  @progress_report_interval_pct 0.01

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

  Options:
    - :progress_callback - function to call with progress updates: fn(%{bytes_read: int, total_bytes: int, encounters_found: int}) -> :ok
  """
  def parse_file_with_bytes(path, start_byte \\ 0, opts \\ []) do
    file = File.open!(path, [:read, :binary])
    {:ok, %{size: total_bytes}} = File.stat(path)
    progress_callback = Keyword.get(opts, :progress_callback)

    try do
      # Seek to start position and align to line boundary
      actual_start_byte =
        if start_byte > 0 do
          :file.position(file, start_byte)
          skip_to_line_boundary(file, start_byte)
        else
          0
        end

      {encounters, current_byte} = read_and_parse(file, actual_start_byte, total_bytes, progress_callback)
      {encounters, current_byte}
    after
      File.close(file)
    end
  end

  @doc """
  Streams encounters from a combat log file, calling a callback for each completed encounter.
  This allows inserting encounters to the database as they're parsed rather than accumulating all in memory.

  The callback receives: fn(encounter, start_byte, end_byte) -> :ok | {:error, reason}
  If the callback returns {:error, reason}, parsing stops and that error is returned.

  Options:
    - :progress_callback - function for progress updates: fn(%{bytes_read: int, total_bytes: int, encounters_found: int}) -> :ok

  Returns {:ok, %{encounters_found: count, end_byte: byte}} on success,
          {:error, reason} if callback fails or file error occurs.
  """
  def stream_encounters(path, start_byte \\ 0, encounter_callback, opts \\ []) do
    # Use :raw mode to avoid Elixir's IO layer mangling UTF-8 bytes
    {:ok, file} = :file.open(path, [:read, :binary, :raw])
    {:ok, %{size: total_bytes}} = File.stat(path)
    progress_callback = Keyword.get(opts, :progress_callback)

    try do
      actual_start_byte =
        if start_byte > 0 do
          :file.position(file, start_byte)
          # Skip the rest of the current line since we might be mid-line
          # Read until we hit a newline to align with line boundaries
          skip_to_line_boundary(file, start_byte)
        else
          0
        end

      state = %{
        current: nil,
        current_start_byte: nil,
        byte_offset: actual_start_byte,
        total_bytes: total_bytes,
        progress_callback: progress_callback,
        encounter_callback: encounter_callback,
        last_progress_report: 0,
        encounters_found: 0,
        error: nil
      }

      result = do_stream_encounters(file, state)

      case result do
        %{error: nil} = final_state ->
          {:ok, %{encounters_found: final_state.encounters_found, end_byte: final_state.byte_offset}}

        %{error: reason} ->
          {:error, reason}
      end
    after
      :file.close(file)
    end
  end

  defp do_stream_encounters(_file, %{error: error} = state) when error != nil do
    state
  end

  defp do_stream_encounters(file, state) do
    # Use :file.read_line to preserve raw bytes (avoids UTF-8 mangling)
    case :file.read_line(file) do
      :eof ->
        maybe_report_stream_progress(state, true)

      {:error, reason} ->
        %{state | error: reason}

      {:ok, line} ->
        if complete_line?(line) do
          {:ok, new_byte_offset} = :file.position(file, :cur)

          parsed = parse_line(line)
          new_state = process_streaming_event(parsed, state, new_byte_offset)
          new_state = maybe_report_stream_progress(%{new_state | byte_offset: new_byte_offset}, false)

          do_stream_encounters(file, new_state)
        else
          # Partial line at EOF - stop here
          maybe_report_stream_progress(state, true)
        end
    end
  end

  defp process_streaming_event({:invalid, _, _}, state, _byte_offset), do: state

  defp process_streaming_event({timestamp, "ENCOUNTER_START", fields}, state, _byte_offset) do
    encounter = Encounter.start(fields, timestamp)
    %{state | current: encounter, current_start_byte: state.byte_offset}
  end

  defp process_streaming_event({_timestamp, "ENCOUNTER_END", _fields}, %{current: nil} = state, _byte_offset) do
    state
  end

  defp process_streaming_event({timestamp, "ENCOUNTER_END", fields}, state, byte_offset) do
    completed_encounter = Encounter.finish(state.current, fields, timestamp)

    # Call the callback to persist this encounter
    case state.encounter_callback.(completed_encounter, state.current_start_byte, byte_offset) do
      :ok ->
        %{state |
          current: nil,
          current_start_byte: nil,
          encounters_found: state.encounters_found + 1
        }

      {:error, reason} ->
        %{state | error: reason}
    end
  end

  defp process_streaming_event({_timestamp, _event_type, _fields}, %{current: nil} = state, _byte_offset) do
    state
  end

  defp process_streaming_event({timestamp, event_type, fields}, state, _byte_offset) do
    event = %{timestamp: timestamp, type: event_type, data: fields}
    updated_encounter = Encounter.add_event(state.current, event)
    %{state | current: updated_encounter}
  end

  defp maybe_report_stream_progress(%{progress_callback: nil} = state, _force), do: state

  defp maybe_report_stream_progress(state, force) do
    %{byte_offset: current, total_bytes: total, last_progress_report: last, progress_callback: callback} = state
    interval = trunc(total * @progress_report_interval_pct)

    if force || current - last >= interval do
      callback.(%{bytes_read: current, total_bytes: total, encounters_found: state.encounters_found})
      %{state | last_progress_report: current}
    else
      state
    end
  end

  defp read_and_parse(file, start_byte, total_bytes, progress_callback) do
    state = %{
      encounters: [],
      current: nil,
      current_lines: [],
      current_start_byte: nil,
      byte_offset: start_byte,
      total_bytes: total_bytes,
      progress_callback: progress_callback,
      last_progress_report: 0
    }

    do_read_and_parse(file, state)
  end

  defp do_read_and_parse(file, state) do
    case IO.read(file, :line) do
      :eof ->
        # Final progress report
        maybe_report_progress(state, true)
        {Enum.reverse(state.encounters), state.byte_offset}

      {:error, _reason} ->
        {Enum.reverse(state.encounters), state.byte_offset}

      line ->
        # Only process complete lines (ending with \n or \r\n)
        # Partial lines occur when WoW is still writing - skip them to avoid
        # storing a byte offset that starts mid-line on next sync
        if complete_line?(line) do
          line_bytes = byte_size(line)
          new_byte_offset = state.byte_offset + line_bytes

          parsed = parse_line(line)
          new_state = process_event_with_bytes(parsed, line, state, new_byte_offset)

          # Report progress periodically
          new_state = maybe_report_progress(%{new_state | byte_offset: new_byte_offset}, false)

          do_read_and_parse(file, new_state)
        else
          # Partial line at EOF - stop here without counting it
          # Next sync will re-read this line once it's complete
          maybe_report_progress(state, true)
          {Enum.reverse(state.encounters), state.byte_offset}
        end
    end
  end

  # A complete line ends with a newline character
  defp complete_line?(line) do
    String.ends_with?(line, "\n")
  end

  # Skip to the next line boundary when resuming from mid-file
  # Returns the byte offset after the newline
  defp skip_to_line_boundary(file, _current_byte) do
    case :file.read_line(file) do
      :eof ->
        {:ok, pos} = :file.position(file, :cur)
        pos

      {:error, _} ->
        {:ok, pos} = :file.position(file, :cur)
        pos

      {:ok, _line} ->
        {:ok, pos} = :file.position(file, :cur)
        pos
    end
  end

  defp maybe_report_progress(%{progress_callback: nil} = state, _force), do: state

  defp maybe_report_progress(state, force) do
    %{byte_offset: current, total_bytes: total, last_progress_report: last, progress_callback: callback} = state
    interval = trunc(total * @progress_report_interval_pct)

    if force || current - last >= interval do
      encounters_found = length(state.encounters)
      callback.(%{bytes_read: current, total_bytes: total, encounters_found: encounters_found})
      %{state | last_progress_report: current}
    else
      state
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
