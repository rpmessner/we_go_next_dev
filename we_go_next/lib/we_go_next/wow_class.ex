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
    # Blood
    250 => @death_knight,
    # Frost
    251 => @death_knight,
    # Unholy
    252 => @death_knight,

    # Demon Hunter
    # Havoc
    577 => @demon_hunter,
    # Vengeance
    581 => @demon_hunter,

    # Druid
    # Balance
    102 => @druid,
    # Feral
    103 => @druid,
    # Guardian
    104 => @druid,
    # Restoration
    105 => @druid,

    # Evoker
    # Devastation
    1467 => @evoker,
    # Preservation
    1468 => @evoker,
    # Augmentation
    1473 => @evoker,

    # Hunter
    # Beast Mastery
    253 => @hunter,
    # Marksmanship
    254 => @hunter,
    # Survival
    255 => @hunter,

    # Mage
    # Arcane
    62 => @mage,
    # Fire
    63 => @mage,
    # Frost
    64 => @mage,

    # Monk
    # Brewmaster
    268 => @monk,
    # Mistweaver
    270 => @monk,
    # Windwalker
    269 => @monk,

    # Paladin
    # Holy
    65 => @paladin,
    # Protection
    66 => @paladin,
    # Retribution
    70 => @paladin,

    # Priest
    # Discipline
    256 => @priest,
    # Holy
    257 => @priest,
    # Shadow
    258 => @priest,

    # Rogue
    # Assassination
    259 => @rogue,
    # Outlaw
    260 => @rogue,
    # Subtlety
    261 => @rogue,

    # Shaman
    # Elemental
    262 => @shaman,
    # Enhancement
    263 => @shaman,
    # Restoration
    264 => @shaman,

    # Warlock
    # Affliction
    265 => @warlock,
    # Demonology
    266 => @warlock,
    # Destruction
    267 => @warlock,

    # Warrior
    # Arms
    71 => @warrior,
    # Fury
    72 => @warrior,
    # Protection
    73 => @warrior
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

  @spec_names %{
    250 => "Blood",
    251 => "Frost",
    252 => "Unholy",
    577 => "Havoc",
    581 => "Vengeance",
    102 => "Balance",
    103 => "Feral",
    104 => "Guardian",
    105 => "Restoration",
    1467 => "Devastation",
    1468 => "Preservation",
    1473 => "Augmentation",
    253 => "Beast Mastery",
    254 => "Marksmanship",
    255 => "Survival",
    62 => "Arcane",
    63 => "Fire",
    64 => "Frost",
    268 => "Brewmaster",
    270 => "Mistweaver",
    269 => "Windwalker",
    65 => "Holy",
    66 => "Protection",
    70 => "Retribution",
    256 => "Discipline",
    257 => "Holy",
    258 => "Shadow",
    259 => "Assassination",
    260 => "Outlaw",
    261 => "Subtlety",
    262 => "Elemental",
    263 => "Enhancement",
    264 => "Restoration",
    265 => "Affliction",
    266 => "Demonology",
    267 => "Destruction",
    71 => "Arms",
    72 => "Fury",
    73 => "Protection"
  }

  @spec_roles %{
    250 => "tank",
    251 => "dps",
    252 => "dps",
    577 => "dps",
    581 => "tank",
    102 => "dps",
    103 => "dps",
    104 => "tank",
    105 => "healer",
    1467 => "dps",
    1468 => "healer",
    1473 => "dps",
    253 => "dps",
    254 => "dps",
    255 => "dps",
    62 => "dps",
    63 => "dps",
    64 => "dps",
    268 => "tank",
    270 => "healer",
    269 => "dps",
    65 => "healer",
    66 => "tank",
    70 => "dps",
    256 => "healer",
    257 => "healer",
    258 => "dps",
    259 => "dps",
    260 => "dps",
    261 => "dps",
    262 => "dps",
    263 => "dps",
    264 => "healer",
    265 => "dps",
    266 => "dps",
    267 => "dps",
    71 => "dps",
    72 => "dps",
    73 => "tank"
  }

  # Official WoW class colors (hex)
  @class_colors %{
    # Tan
    @warrior => "#C69B6D",
    # Pink
    @paladin => "#F48CBA",
    # Green
    @hunter => "#AAD372",
    # Yellow
    @rogue => "#FFF468",
    # White
    @priest => "#FFFFFF",
    # Red
    @death_knight => "#C41E3A",
    # Blue
    @shaman => "#0070DD",
    # Light Blue
    @mage => "#3FC7EB",
    # Purple
    @warlock => "#8788EE",
    # Jade Green
    @monk => "#00FF98",
    # Orange
    @druid => "#FF7C0A",
    # Dark Magenta
    @demon_hunter => "#A330C9",
    # Teal/Dark Cyan
    @evoker => "#33937F"
  }

  # Tailwind classes for each WoW class (approximations of official colors)
  @class_tailwind %{
    # Tan - C69B6D
    @warrior => "text-amber-600",
    # Pink - F48CBA
    @paladin => "text-pink-400",
    # Green - AAD372
    @hunter => "text-lime-400",
    # Yellow - FFF468
    @rogue => "text-yellow-300",
    # White - FFFFFF
    @priest => "text-zinc-100",
    # Red - C41E3A
    @death_knight => "text-red-600",
    # Blue - 0070DD
    @shaman => "text-blue-500",
    # Light Blue - 3FC7EB
    @mage => "text-cyan-400",
    # Purple - 8788EE
    @warlock => "text-violet-400",
    # Jade Green - 00FF98
    @monk => "text-emerald-400",
    # Orange - FF7C0A
    @druid => "text-orange-500",
    # Dark Magenta - A330C9
    @demon_hunter => "text-purple-500",
    # Teal - 33937F
    @evoker => "text-teal-500"
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
  Returns the specialization name for a spec ID.
  """
  def spec_name(spec_id) when is_integer(spec_id) do
    Map.get(@spec_names, spec_id, "Unknown")
  end

  def spec_name(_), do: "Unknown"

  @doc """
  Returns the trinity role for a spec ID: tank, healer, or dps.
  """
  def role_from_spec(spec_id) when is_integer(spec_id) do
    Map.get(@spec_roles, spec_id)
  end

  def role_from_spec(_), do: nil

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
