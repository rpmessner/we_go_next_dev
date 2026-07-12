if System.get_env("WE_GO_NEXT_BUILD") != "public" and
     System.get_env("WE_GO_NEXT_MODE") != "public" do
  defmodule WeGoNext.CombatLogParser do
    @moduledoc """
    Native combat log parser for WoW combat logs.

    Provides two main functions:
    - `scan_boundaries/2` - Fast scan for encounter start/end byte offsets
    - `parse_events/4` - Parse all events within an encounter's byte range

    Handles the performance-critical parsing work: timestamp extraction,
    CSV splitting, field normalization. Results are returned as Elixir-native
    terms (maps, lists, strings).
    """

    use Zig,
      otp_app: :we_go_next,
      zig_code_path: "./priv/native/combat_log_parser.zig",
      nifs: [
        scan_boundaries: [spec: false],
        parse_events: [spec: false]
      ]

    @spec scan_boundaries(String.t(), non_neg_integer()) ::
            {:ok, [map()], non_neg_integer()} | {:error, term()}
    @spec parse_events(String.t(), non_neg_integer(), non_neg_integer(), String.t()) ::
            {:ok, [map()]} | {:error, term()}
  end
else
  defmodule WeGoNext.CombatLogParser do
    @moduledoc false

    @spec scan_boundaries(String.t(), non_neg_integer()) ::
            {:ok, [map()], non_neg_integer()} | {:error, term()}
    def scan_boundaries(_path, _start_byte), do: unavailable_result()

    @spec parse_events(String.t(), non_neg_integer(), non_neg_integer(), String.t()) ::
            {:ok, [map()]} | {:error, term()}
    def parse_events(_path, _start_byte, _end_byte, _start_timestamp),
      do: unavailable_result()

    defp unavailable_result do
      Application.get_env(
        :we_go_next,
        :public_parser_unavailable_result,
        {:error, :parser_unavailable}
      )
    end
  end
end
