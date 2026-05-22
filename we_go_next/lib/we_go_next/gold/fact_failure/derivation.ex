defmodule WeGoNext.Gold.FactFailure.Derivation do
  @moduledoc """
  Version stamp for `gold.fact_failure` builder semantics.

  Bump this when the fact builders change in a way that requires existing facts
  to be rebuilt from silver rows.
  """

  @current_version 1

  def current_version, do: @current_version
end
