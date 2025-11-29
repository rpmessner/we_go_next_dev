defmodule WeGoNextWeb.Features.AutoUpdateTest do
  @moduledoc """
  DEFERRED: Auto-polling tests

  These tests were designed for automatic FileWatcher polling, which has been
  deferred in favor of manual refresh. WoW's combat log buffering during active
  combat made auto-polling unreliable (file would change but no complete
  encounters until ENCOUNTER_END).

  Manual refresh via the UI is the current approach for MVP.
  See docs/ROADMAP.md Phase 4 for details.

  Original test scenarios:
  1. dashboard auto-updates when FileWatcher detects new encounters
  2. multiple auto-updates as encounters are added
  """
  use ExUnit.Case, async: false

  @tag :skip
  test "auto-polling tests deferred - see module docs" do
    # Auto-polling has been removed in favor of manual refresh
    # These tests will be re-enabled if auto-polling is revisited post-MVP
  end
end
