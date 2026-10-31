defmodule WeGoNext.Integration.Pages.FailuresPage do
  @moduledoc """
  Page object for the gold-backed mechanic failures dashboard.
  """
  use Wallaby.DSL

  def navigate(session) do
    visit(session, "/failures")
  end

  def ensure_page_loaded(session) do
    session
    |> assert_has(Query.css("h1", text: "Mechanic Failures"))

    session
  end

  def assert_stat(session, label, value) do
    session
    |> assert_has(Query.css(".stat-block", text: "#{value}\n#{label}"))

    session
  end

  def assert_player_group(session, player_name, player_guid) do
    session
    |> assert_has(Query.css("section", text: player_name))
    |> assert_has(Query.css("section", text: player_guid))

    session
  end

  def assert_failure_row(session, attrs) do
    spell_id = Map.fetch!(attrs, :spell_id)

    # Wowhead may rewrite link text to its canonical name after page load.
    row =
      session
      |> find(Query.css("tr:has(a[href*='spell=#{spell_id}'])"))
      |> Wallaby.Element.text()

    [
      Map.fetch!(attrs, :mechanic_type),
      to_string(Map.fetch!(attrs, :failure_count)),
      to_string(Map.fetch!(attrs, :total_damage)),
      to_string(Map.fetch!(attrs, :encounter_count))
    ]
    |> Enum.each(fn expected ->
      ExUnit.Assertions.assert(
        String.contains?(row, expected),
        "Expected failure row to contain #{inspect(expected)}, got: #{inspect(row)}"
      )
    end)

    session
  end
end
