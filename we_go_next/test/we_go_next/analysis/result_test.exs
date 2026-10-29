defmodule WeGoNext.Analysis.ResultTest do
  use ExUnit.Case, async: true
  alias WeGoNext.Analysis.Result

  test "cap includes evidence and cursors, and continuation loses no rows" do
    rows = for n <- 1..70, do: {%{id: n, value: String.duplicate("界", 70)}, %{pull_id: n}}
    assert {:ok, first} = Result.page(rows, %{}, {"tool", "session"})
    assert first.truncated
    assert byte_size(Jason.encode!(first)) <= 8_192
    all = drain(rows, first, first.data)
    assert Enum.map(all, & &1.id) == Enum.to_list(1..70)

    assert {:error, _} =
             Result.page(rows, %{"cursor" => first.next_cursor}, {"tool", "other-session"})
  end

  test "invalid cursors and single oversized rows are Tool errors" do
    assert {:error, _} = Result.page([], %{"cursor" => "junk"}, "scope")
    assert {:error, _} = Result.page([{String.duplicate("a", 9_000), %{}}], %{}, "scope")
  end

  defp drain(_rows, %{truncated: false}, accumulated), do: accumulated

  defp drain(rows, page, accumulated) do
    assert {:ok, next} = Result.page(rows, %{"cursor" => page.next_cursor}, {"tool", "session"})
    assert byte_size(Jason.encode!(next)) <= 8_192
    drain(rows, next, accumulated ++ next.data)
  end
end
