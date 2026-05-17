defmodule WeGoNext.Silver.Projection do
  @moduledoc """
  Table-shaped silver projection rows for a single encounter.
  """

  @enforce_keys [
    :damage_taken,
    :damage_done,
    :death,
    :interrupt_opportunity,
    :debuff_application,
    :player_info
  ]

  defstruct [
    :damage_taken,
    :damage_done,
    :death,
    :interrupt_opportunity,
    :debuff_application,
    :player_info
  ]
end
