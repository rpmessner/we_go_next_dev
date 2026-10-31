defmodule WeGoNext.CombatLogParser do
  @moduledoc """
  Native combat log parser for WoW combat logs.

  Provides three native entry points:
  - `scan_boundaries/2` - Fast scan for encounter start/end byte offsets
  - `parse_events/4` - Parse all events within an encounter's byte range
  - `parse_events_filtered/5` - Read a bronze slice, rejecting non-matching
    lines before constructing Erlang terms; each event adds `:byte_offset`
    (the absolute file offset of its line).

  The filtered entry point takes the same first four arguments as `parse_events/4`
  and an atom-keyed filter map. Optional `:event_types`, `:source_guids`,
  `:target_guids` are lists of exact strings; `:spell_ids` is a list of integers.
  Omitted or empty lists are unrestricted. Values within a list are ORed;
  different filters are ANDed. GUIDs match only their named prefix field, never
  advanced owner/info GUIDs. Spell ids match `:spell_id`, not interrupt extra
  spells; melee and environmental damage have synthetic id 0, as in imports.
  Optional `:time_min_ms` / `:time_max_ms` are inclusive, signed integer
  milliseconds relative to the supplied encounter start timestamp. Nil bounds
  are unrestricted. Events without a requested field cannot match that filter.

  Byte ranges are `[start_byte, end_byte)`, with line-aligned bounds supplied by
  encounter boundaries. As with imports, only newline-terminated lines are
  parsed (including CRLF). Events retain file order. This low-level reader does
  not cap results or resolve bronze paths; the calling Tool owns those concerns.

  Handles the performance-critical parsing work: timestamp extraction,
  CSV splitting, field normalization. Results are returned as Elixir-native
  terms (maps, lists, strings).
  """

  use Zig,
    otp_app: :we_go_next,
    zig_code_path: "./priv/native/combat_log_parser.zig",
    # Keep local imports fast without holding a normal BEAM scheduler.
    optimize: :safe,
    nifs: [
      scan_boundaries: [spec: false, concurrency: :dirty_cpu],
      parse_events: [spec: false, concurrency: :dirty_cpu],
      parse_events_filtered: [spec: false, concurrency: :dirty_cpu]
    ]

  @spec scan_boundaries(String.t(), non_neg_integer()) ::
          {:ok, [map()], non_neg_integer()} | {:error, term()}
  @spec parse_events(String.t(), non_neg_integer(), non_neg_integer(), String.t()) ::
          {:ok, [map()]} | {:error, term()}
  @spec parse_events_filtered(
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          String.t(),
          map()
        ) :: {:ok, [map()]} | {:error, term()}
end
