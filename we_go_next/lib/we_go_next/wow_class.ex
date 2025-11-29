defmodule WeGoNext.WowClass do
  @moduledoc """
  WoW class definitions, spec mappings, and class colors.

  Class colors are the official WoW class colors used in-game and on sites like Wowhead.
  """

  # WoW Class IDs
  @warrior 1
  @paladin 2
  @hunter 3
  @rogue 4
  @priest 5
  @death_knight 6
  @shaman 7
  @mage 8
  @warlock 9
  @monk 10
  @druid 11
  @demon_hunter 12
  @evoker 13

  # Spec ID -> Class ID mapping
  # See: https://wowpedia.fandom.com/wiki/SpecializationID
  @spec_to_class %{
    # Death Knight
    250 => @death_knight,  # Blood
    251 => @death_knight,  # Frost
    252 => @death_knight,  # Unholy

    # Demon Hunter
    577 => @demon_hunter,  # Havoc
    581 => @demon_hunter,  # Vengeance

    # Druid
    102 => @druid,  # Balance
    103 => @druid,  # Feral
    104 => @druid,  # Guardian
    105 => @druid,  # Restoration

    # Evoker
    1467 => @evoker,  # Devastation
    1468 => @evoker,  # Preservation
    1473 => @evoker,  # Augmentation

    # Hunter
    253 => @hunter,  # Beast Mastery
    254 => @hunter,  # Marksmanship
    255 => @hunter,  # Survival

    # Mage
    62 => @mage,   # Arcane
    63 => @mage,   # Fire
    64 => @mage,   # Frost

    # Monk
    268 => @monk,  # Brewmaster
    270 => @monk,  # Mistweaver
    269 => @monk,  # Windwalker

    # Paladin
    65 => @paladin,   # Holy
    66 => @paladin,   # Protection
    70 => @paladin,   # Retribution

    # Priest
    256 => @priest,  # Discipline
    257 => @priest,  # Holy
    258 => @priest,  # Shadow

    # Rogue
    259 => @rogue,  # Assassination
    260 => @rogue,  # Outlaw
    261 => @rogue,  # Subtlety

    # Shaman
    262 => @shaman,  # Elemental
    263 => @shaman,  # Enhancement
    264 => @shaman,  # Restoration

    # Warlock
    265 => @warlock,  # Affliction
    266 => @warlock,  # Demonology
    267 => @warlock,  # Destruction

    # Warrior
    71 => @warrior,  # Arms
    72 => @warrior,  # Fury
    73 => @warrior   # Protection
  }

  # Class ID -> Name
  @class_names %{
    @warrior => "Warrior",
    @paladin => "Paladin",
    @hunter => "Hunter",
    @rogue => "Rogue",
    @priest => "Priest",
    @death_knight => "Death Knight",
    @shaman => "Shaman",
    @mage => "Mage",
    @warlock => "Warlock",
    @monk => "Monk",
    @druid => "Druid",
    @demon_hunter => "Demon Hunter",
    @evoker => "Evoker"
  }

  # Official WoW class colors (hex)
  @class_colors %{
    @warrior => "#C69B6D",      # Tan
    @paladin => "#F48CBA",      # Pink
    @hunter => "#AAD372",       # Green
    @rogue => "#FFF468",        # Yellow
    @priest => "#FFFFFF",       # White
    @death_knight => "#C41E3A", # Red
    @shaman => "#0070DD",       # Blue
    @mage => "#3FC7EB",         # Light Blue
    @warlock => "#8788EE",      # Purple
    @monk => "#00FF98",         # Jade Green
    @druid => "#FF7C0A",        # Orange
    @demon_hunter => "#A330C9", # Dark Magenta
    @evoker => "#33937F"        # Teal/Dark Cyan
  }

  # Tailwind classes for each WoW class (approximations of official colors)
  @class_tailwind %{
    @warrior => "text-amber-600",        # Tan - C69B6D
    @paladin => "text-pink-400",         # Pink - F48CBA
    @hunter => "text-lime-400",          # Green - AAD372
    @rogue => "text-yellow-300",         # Yellow - FFF468
    @priest => "text-zinc-100",          # White - FFFFFF
    @death_knight => "text-red-600",     # Red - C41E3A
    @shaman => "text-blue-500",          # Blue - 0070DD
    @mage => "text-cyan-400",            # Light Blue - 3FC7EB
    @warlock => "text-violet-400",       # Purple - 8788EE
    @monk => "text-emerald-400",         # Jade Green - 00FF98
    @druid => "text-orange-500",         # Orange - FF7C0A
    @demon_hunter => "text-purple-500",  # Dark Magenta - A330C9
    @evoker => "text-teal-500"           # Teal - 33937F
  }

  @doc """
  Returns the class ID for a given spec ID.
  """
  def class_from_spec(spec_id) when is_integer(spec_id) do
    Map.get(@spec_to_class, spec_id)
  end
  def class_from_spec(_), do: nil

  @doc """
  Returns the class name for a class ID.
  """
  def class_name(class_id) when is_integer(class_id) do
    Map.get(@class_names, class_id, "Unknown")
  end
  def class_name(_), do: "Unknown"

  @doc """
  Returns the hex color code for a class ID.
  """
  def class_color(class_id) when is_integer(class_id) do
    Map.get(@class_colors, class_id, "#FFFFFF")
  end
  def class_color(_), do: "#FFFFFF"

  @doc """
  Returns the Tailwind CSS class for a class ID.
  """
  def class_tailwind(class_id) when is_integer(class_id) do
    Map.get(@class_tailwind, class_id, "text-zinc-200")
  end
  def class_tailwind(_), do: "text-zinc-200"

  @doc """
  Returns the hex color code for a spec ID.
  """
  def color_for_spec(spec_id) do
    case class_from_spec(spec_id) do
      nil -> "#FFFFFF"
      class_id -> class_color(class_id)
    end
  end

  @doc """
  Returns the Tailwind CSS class for a spec ID.
  """
  def tailwind_for_spec(spec_id) do
    case class_from_spec(spec_id) do
      nil -> "text-zinc-200"
      class_id -> class_tailwind(class_id)
    end
  end

  @doc """
  Returns the CSS style attribute for inline class coloring.
  """
  def style_for_class(class_id) do
    "color: #{class_color(class_id)}"
  end

  @doc """
  Returns the CSS style attribute for inline spec coloring.
  """
  def style_for_spec(spec_id) do
    "color: #{color_for_spec(spec_id)}"
  end

  # Export constants for use in other modules
  def warrior, do: @warrior
  def paladin, do: @paladin
  def hunter, do: @hunter
  def rogue, do: @rogue
  def priest, do: @priest
  def death_knight, do: @death_knight
  def shaman, do: @shaman
  def mage, do: @mage
  def warlock, do: @warlock
  def monk, do: @monk
  def druid, do: @druid
  def demon_hunter, do: @demon_hunter
  def evoker, do: @evoker
end
