defmodule WeGoNext.Analyzers.PlayerInfoAnalyzer do
  @moduledoc """
  Legacy reference-only analyzer for player class/spec hints.

  Retained for command-line diagnostics, migration reference, and parity checks.
  New medallion UI, gold facts, and silver/gold read models must not depend on
  this module or its in-memory output shape.

  Extracts player information (class, spec) from COMBATANT_INFO events.

  COMBATANT_INFO is logged at the start of each encounter and contains:
  - Player GUID
  - Stats (strength, agility, stamina, intellect, etc.)
  - Spec ID (used to determine class)
  - Talent information
  - Gear information

  Format (key fields):
  COMBATANT_INFO,PlayerGUID,?, stats..., specID, talents, gear, buffs, pvpTier, ...

  The spec ID is at index 24 (0-based) after the event type.
  """

  alias WeGoNext.{Encounter, WowClass}

  defmodule PlayerInfo do
    @moduledoc "Player information extracted from COMBATANT_INFO"
    defstruct [:player_guid, :spec_id, :class_id]
  end

  @doc """
  Extracts a map of player_guid => class_id from an encounter's events.

  Returns a map like:
  %{
    "Player-1171-08FEC59B" => 1,  # Warrior
    "Player-3725-0C095B74" => 9   # Warlock
  }
  """
  def analyze(%Encounter{events: events}) do
    events
    |> Enum.reduce(%{}, fn event, acc ->
      case process_event(event) do
        {:ok, player_guid, class_id} when not is_nil(class_id) ->
          Map.put(acc, player_guid, class_id)

        _ ->
          acc
      end
    end)
  end

  # Now using normalized event fields - COMBATANT_INFO stores class/spec in extra
  defp process_event(%{type: "COMBATANT_INFO"} = event) do
    player_guid = event.source_guid

    # Class and spec are stored in the extra map during parsing
    class_id = get_in(event, [:extra, "class_id"])
    spec_id = get_in(event, [:extra, "spec_id"])

    # If we have spec_id but not class_id, derive class from spec
    class_id = class_id || (spec_id && WowClass.class_from_spec(spec_id))

    if class_id do
      {:ok, player_guid, class_id}
    else
      :error
    end
  end

  defp process_event(_), do: :error

  @doc """
  Returns a map of player_name => class_id by correlating with damage/death events.

  Since COMBATANT_INFO only has GUIDs, we need to match them with names from
  other events. Returns a map suitable for UI display.
  """
  def player_classes_by_name(%Encounter{events: events} = encounter) do
    # First get GUID -> class_id mapping
    guid_to_class = analyze(encounter)

    # Then build GUID -> name mapping from other events
    guid_to_name = build_guid_to_name_map(events)

    # Combine them: name -> class_id
    guid_to_class
    |> Enum.reduce(%{}, fn {guid, class_id}, acc ->
      case Map.get(guid_to_name, guid) do
        nil -> acc
        name -> Map.put(acc, name, class_id)
      end
    end)
  end

  # Build a mapping of player GUIDs to names from combat events
  defp build_guid_to_name_map(events) do
    events
    |> Enum.reduce(%{}, fn event, acc ->
      case extract_player_info_from_event(event) do
        nil -> acc
        {guid, name} -> Map.put_new(acc, guid, name)
      end
    end)
  end

  # Extract player GUID and name from various event types (now using normalized fields)
  defp extract_player_info_from_event(%{type: type} = event)
       when type in [
              "SPELL_DAMAGE",
              "SPELL_CAST_SUCCESS",
              "SPELL_AURA_APPLIED",
              "SWING_DAMAGE",
              "UNIT_DIED",
              "SPELL_HEAL"
            ] do
    # Source player
    source_guid = event.source_guid
    source_name = event.source_name

    cond do
      player_guid?(source_guid) ->
        {source_guid, clean_name(source_name)}

      # Target player for damage/heal events
      player_guid?(event.target_guid) ->
        {event.target_guid, clean_name(event.target_name)}

      true ->
        nil
    end
  end

  defp extract_player_info_from_event(_), do: nil

  defp player_guid?(guid) when is_binary(guid), do: String.starts_with?(guid, "Player-")
  defp player_guid?(_), do: false

  # Clean player name (remove realm suffix if present)
  defp clean_name(name) when is_binary(name) do
    name
    |> String.split("-")
    |> List.first()
  end

  defp clean_name(name), do: name
end
