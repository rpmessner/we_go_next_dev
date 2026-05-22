defmodule WeGoNext.Silver.Projection do
  @moduledoc """
  Table-shaped silver projection rows for a single encounter.
  """

  @enforce_keys [
    :damage_taken,
    :damage_taken_event,
    :damage_done,
    :death,
    :interrupt_opportunity,
    :debuff_application,
    :defensive_buff_window,
    :player_info
  ]

  defstruct [
    :damage_taken,
    :damage_taken_event,
    :damage_done,
    :death,
    :interrupt_opportunity,
    :debuff_application,
    :defensive_buff_window,
    :player_info
  ]

  @type t :: %__MODULE__{
          damage_taken: [map()],
          damage_taken_event: [map()],
          damage_done: [map()],
          death: [map()],
          interrupt_opportunity: [map()],
          debuff_application: [map()],
          defensive_buff_window: [map()],
          player_info: [map()]
        }
end
