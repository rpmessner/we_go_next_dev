defmodule WeGoNextWeb.Features.LogRotationTest do
  @moduledoc """
  DEFERRED: Log rotation auto-detection tests

  These tests were designed for automatic FileWatcher polling to detect when
  WoW creates a new log file. This functionality depended on auto-polling which
  has been deferred in favor of manual refresh.

  WoW creates new log files when:
  - Game is launched
  - Player does /reload
  - Player toggles /combatlog off and on
  - New day rolls over (sometimes)

  File naming format: WoWCombatLog-MMDDYY_HHMMSS.txt

  For MVP, users can manually select new log files from the dropdown when they
  notice WoW has created a new one.

  See docs/ROADMAP.md Phase 4 for details.

  Original test scenarios:
  1. detects new log file and switches to watching it
  2. handles rotation while preserving encounter history
  """
  use ExUnit.Case, async: false

  @tag :skip
  test "log rotation auto-detection deferred - see module docs" do
    # Auto-detection of log rotation has been removed with auto-polling
    # Users manually select new logs from the dropdown for MVP
  end
end
