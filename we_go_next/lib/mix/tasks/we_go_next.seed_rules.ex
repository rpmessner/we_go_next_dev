defmodule Mix.Tasks.WeGoNext.SeedRules do
  @moduledoc "Compatibility alias for syncing the live current-tier mechanics catalog."
  use Mix.Task
  @shortdoc "Sync the live current-tier mechanics catalog"

  @impl Mix.Task
  def run(args) do
    if args != [], do: Mix.raise("JSON seeds are retired; use mix we_go_next.sync_raid_rules")
    Mix.Tasks.WeGoNext.SyncRaidRules.run([])
  end
end
