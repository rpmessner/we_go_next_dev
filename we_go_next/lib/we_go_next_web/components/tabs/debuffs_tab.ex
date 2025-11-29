defmodule WeGoNextWeb.Components.Tabs.DebuffsTab do
  @moduledoc """
  Debuffs tab component for encounter detail view.

  Displays debuff analysis:
  - Filter controls for player-applied debuffs
  - Boss mechanics (debuffs) table
  - Pinned and hidden debuff management
  - Players with most debuffs
  """
  use Phoenix.Component

  import WeGoNextWeb.EncounterComponents

  alias WeGoNext.Analyzers.DebuffAnalyzer

  attr :stats, :map, required: true
  attr :show_player_debuffs, :boolean, required: true
  attr :hidden_spell_ids, :any, required: true
  attr :force_shown_spell_ids, :any, required: true
  attr :is_admin, :boolean, required: true
  attr :player_classes, :map, required: true

  def render(assigns) do
    # Use shared helper for filtering
    debuffs = filtered_debuffs(assigns.stats, assigns.hidden_spell_ids, assigns.force_shown_spell_ids, assigns.show_player_debuffs)
    assigns = assign(assigns, :filtered_debuffs, debuffs)

    ~H"""
    <div class="space-y-6" id="debuffs-tab" phx-hook="WowheadTooltips">
      <%!-- Filters panel --%>
      <div class="bg-zinc-800 rounded-lg p-4">
        <div class="flex items-center justify-between">
          <h3 class="text-sm font-medium text-zinc-300">Filters</h3>
          <label class="flex items-center gap-2 cursor-pointer">
            <input
              type="checkbox"
              checked={@show_player_debuffs}
              phx-click="toggle_player_debuffs"
              class="rounded border-zinc-600 bg-zinc-700 text-blue-500 focus:ring-blue-500 focus:ring-offset-zinc-800"
            />
            <span class="text-sm text-zinc-400">Show player-applied debuffs</span>
          </label>
        </div>
      </div>

      <%!-- Top debuffs by application count --%>
      <div>
        <h3 class="text-sm font-medium text-zinc-400 mb-3">Boss Mechanics (Debuffs)</h3>
        <div class="bg-zinc-800 rounded-lg overflow-hidden">
          <table class="w-full">
            <thead class="bg-zinc-750">
              <tr>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Debuff</th>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Source</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Applications</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Players Hit</th>
                <th :if={@is_admin} class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Actions</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-700">
              <tr
                :for={debuff <- @filtered_debuffs}
                class="hover:bg-zinc-750"
              >
                <td class="px-4 py-2">
                  <span :if={MapSet.member?(@force_shown_spell_ids, debuff.spell_id)} class="text-blue-400 mr-1" title="Pinned - always shown">
                    📌
                  </span>
                  <a
                    href={"https://www.wowhead.com/spell=#{debuff.spell_id}"}
                    target="_blank"
                    rel="noopener"
                  >
                    {debuff.name}
                  </a>
                </td>
                <td class="px-4 py-2 text-zinc-500 text-sm">{debuff.source_name}</td>
                <td class="px-4 py-2 text-right text-zinc-400">{debuff.count}</td>
                <td class="px-4 py-2 text-right text-zinc-500">{debuff.players}</td>
                <td :if={@is_admin} class="px-4 py-2 text-right space-x-2">
                  <%!-- Pin button - only show for non-NPC sourced debuffs that need pinning --%>
                  <button
                    :if={not DebuffAnalyzer.npc_source?(debuff.source_guid)}
                    phx-click="toggle_force_show"
                    phx-value-spell-id={debuff.spell_id}
                    phx-value-spell-name={debuff.name}
                    class={[
                      "text-xs",
                      if(MapSet.member?(@force_shown_spell_ids, debuff.spell_id),
                        do: "text-blue-400 hover:text-blue-300",
                        else: "text-zinc-500 hover:text-blue-400")
                    ]}
                    title={if MapSet.member?(@force_shown_spell_ids, debuff.spell_id), do: "Unpin this debuff", else: "Pin this debuff (always show)"}
                  >
                    {if MapSet.member?(@force_shown_spell_ids, debuff.spell_id), do: "Unpin", else: "Pin"}
                  </button>
                  <button
                    phx-click="toggle_spell_visibility"
                    phx-value-spell-id={debuff.spell_id}
                    phx-value-spell-name={debuff.name}
                    class="text-xs text-zinc-500 hover:text-red-400"
                    title="Hide this debuff"
                  >
                    Hide
                  </button>
                </td>
              </tr>
              <tr :if={@filtered_debuffs == []} class="hover:bg-zinc-750">
                <td colspan={if @is_admin, do: 5, else: 4} class="px-4 py-4 text-center text-zinc-500">
                  No debuffs to display. Try enabling "Show player-applied debuffs" above.
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <%!-- Pinned debuffs (admin only) --%>
      <div :if={@is_admin && MapSet.size(@force_shown_spell_ids) > 0}>
        <h3 class="text-sm font-medium text-blue-400 mb-3">📌 Pinned Debuffs ({MapSet.size(@force_shown_spell_ids)})</h3>
        <p class="text-xs text-zinc-500 mb-2">These debuffs are always shown, even when "Show player-applied debuffs" is off.</p>
        <div class="bg-zinc-800/50 rounded-lg p-3">
          <div class="flex flex-wrap gap-2">
            <%= for debuff <- pinned_debuffs(@stats, @force_shown_spell_ids) do %>
              <button
                phx-click="toggle_force_show"
                phx-value-spell-id={debuff.spell_id}
                phx-value-spell-name={debuff.name}
                class="inline-flex items-center gap-1 px-2 py-1 bg-blue-900/30 border border-blue-800 rounded text-xs text-blue-300 hover:bg-blue-800/30"
              >
                {debuff.name}
                <span class="text-zinc-500">×</span>
              </button>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Hidden debuffs (admin only) --%>
      <div :if={@is_admin && MapSet.size(@hidden_spell_ids) > 0}>
        <h3 class="text-sm font-medium text-zinc-500 mb-3">Hidden Debuffs ({MapSet.size(@hidden_spell_ids)})</h3>
        <div class="bg-zinc-800/50 rounded-lg p-3">
          <div class="flex flex-wrap gap-2">
            <%= for debuff <- hidden_debuffs(@stats, @hidden_spell_ids) do %>
              <button
                phx-click="toggle_spell_visibility"
                phx-value-spell-id={debuff.spell_id}
                phx-value-spell-name={debuff.name}
                class="inline-flex items-center gap-1 px-2 py-1 bg-zinc-700 rounded text-xs text-zinc-400 hover:bg-zinc-600"
              >
                {debuff.name}
                <span class="text-green-400">+</span>
              </button>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Players with most debuffs --%>
      <div>
        <h3 class="text-sm font-medium text-zinc-400 mb-3">Players with Most Debuffs</h3>
        <div class="bg-zinc-800 rounded-lg overflow-hidden">
          <table class="w-full">
            <thead class="bg-zinc-750">
              <tr>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Player</th>
                <th class="text-right text-xs font-medium text-zinc-400 px-4 py-2">Debuffs</th>
                <th class="text-left text-xs font-medium text-zinc-400 px-4 py-2">Types</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-zinc-700">
              <tr :for={{name, data} <- players_by_debuffs(@stats, @hidden_spell_ids, @show_player_debuffs)} class="hover:bg-zinc-750">
                <td class="px-4 py-2">
                  <.player_name name={name} player_classes={@player_classes} />
                </td>
                <td class="px-4 py-2 text-right text-zinc-400">{data.count}</td>
                <td class="px-4 py-2 text-zinc-500 text-sm">
                  {data.spells |> Enum.take(3) |> Enum.join(", ")}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp top_debuffs(stats) do
    stats.by_spell
    |> Enum.map(fn {name, data} ->
      %{
        name: name,
        count: data.total_applications,
        players: data.players_affected,
        spell_id: data.spell_id,
        # Handle cached data that might not have source_guid/source_name
        source_guid: Map.get(data, :source_guid),
        source_name: Map.get(data, :source_name, "Unknown")
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(25)
  end

  # Filter debuffs based on hidden spells, force-shown spells, and show_player_debuffs toggle
  defp filtered_debuffs(stats, hidden_spell_ids, force_shown_spell_ids, show_player_debuffs) do
    top_debuffs(stats)
    |> Enum.reject(fn debuff ->
      MapSet.member?(hidden_spell_ids, debuff.spell_id)
    end)
    |> Enum.filter(fn debuff ->
      cond do
        # Force-shown debuffs always appear (overrides player-applied classification)
        MapSet.member?(force_shown_spell_ids, debuff.spell_id) -> true
        # When toggle is on, show all non-hidden debuffs
        show_player_debuffs -> true
        # Otherwise only show NPC-sourced debuffs
        true -> DebuffAnalyzer.npc_source?(debuff.source_guid)
      end
    end)
  end

  defp hidden_debuffs(stats, hidden_spell_ids) do
    stats.by_spell
    |> Enum.filter(fn {_name, data} ->
      MapSet.member?(hidden_spell_ids, data.spell_id)
    end)
    |> Enum.map(fn {name, data} ->
      %{name: name, spell_id: data.spell_id}
    end)
  end

  defp pinned_debuffs(stats, force_shown_spell_ids) do
    stats.by_spell
    |> Enum.filter(fn {_name, data} ->
      MapSet.member?(force_shown_spell_ids, data.spell_id)
    end)
    |> Enum.map(fn {name, data} ->
      %{name: name, spell_id: data.spell_id}
    end)
  end

  defp players_by_debuffs(stats, hidden_spell_ids, show_player_debuffs) do
    # Build a lookup from spell_name to spell metadata for filtering
    spell_lookup =
      stats.by_spell
      |> Enum.map(fn {name, data} ->
        {name, %{spell_id: Map.get(data, :spell_id), source_guid: Map.get(data, :source_guid)}}
      end)
      |> Map.new()

    stats.by_player
    |> Enum.map(fn {name, data} ->
      # Get the player's spells - handle both struct (by_spell) and cached map (spells) formats
      player_spells = get_player_spells(data)

      # Filter spells for this player using the same logic as the main list
      filtered_spells = Enum.filter(player_spells, fn spell_name ->
        case Map.get(spell_lookup, spell_name) do
          nil -> false
          %{spell_id: spell_id, source_guid: source_guid} ->
            not MapSet.member?(hidden_spell_ids, spell_id) and
              (show_player_debuffs or DebuffAnalyzer.npc_source?(source_guid))
        end
      end)
      player_name = Map.get(data, :player_name) || name
      {player_name, %{spells: filtered_spells, count: length(filtered_spells)}}
    end)
    |> Enum.reject(fn {_, data} -> data.spells == [] end)
    |> Enum.sort_by(fn {_, data} -> data.count end, :desc)
    |> Enum.take(10)
  end

  # Get player spells from either fresh analysis (by_spell map) or cached data (spells list)
  defp get_player_spells(data) do
    cond do
      # Fresh analysis - PlayerStats struct with by_spell map
      Map.has_key?(data, :by_spell) -> Map.keys(data.by_spell)
      # Cached data - map with spells list
      Map.has_key?(data, :spells) -> data.spells
      true -> []
    end
  end
end
