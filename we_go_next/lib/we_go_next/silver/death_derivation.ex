defmodule WeGoNext.Silver.DeathDerivation do
  @moduledoc """
  Version of the death projection, stamped per encounter (including zero deaths).

  Version 1 was unstamped and included Feign Death. Version 2 excludes
  unconscious UNIT_DIED events. Only a bronze-to-silver projection may stamp
  this version; gold/document rebuilds cannot repair stale silver.
  """

  @current_version 2

  def current_version, do: @current_version
end
