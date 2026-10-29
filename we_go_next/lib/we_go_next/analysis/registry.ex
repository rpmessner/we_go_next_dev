defmodule WeGoNext.Analysis.Registry do
  @moduledoc "Enabled Tools as data. Later phase-one Tools register here."
  alias WeGoNext.Analysis.Tools.{ListPulls, SessionContext}
  @tools [SessionContext, ListPulls]
  def tools, do: @tools
  def fetch(name), do: Enum.find(@tools, &(&1.name() == name))

  def definitions do
    Enum.map(
      @tools,
      &%{name: &1.name(), description: &1.description(), inputSchema: &1.input_schema()}
    )
  end
end
