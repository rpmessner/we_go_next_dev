defmodule CombatLogParserTest do
  use ExUnit.Case
  doctest CombatLogParser

  test "greets the world" do
    assert CombatLogParser.hello() == :world
  end
end
