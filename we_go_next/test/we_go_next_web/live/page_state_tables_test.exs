defmodule WeGoNextWeb.PageStateTablesTest do
  use ExUnit.Case, async: true

  alias WeGoNextWeb.{
    DocumentIndexState,
    ImportState,
    LoadState,
    LogSelectionState,
    PathState,
    SortState
  }

  @machines [DocumentIndexState, ImportState, LoadState, LogSelectionState, PathState, SortState]

  test "tables are total, reachable and match their checked-in diagrams and matrices" do
    root = Path.expand("../../../../docs/state-machines/page-state", __DIR__)

    for machine <- @machines do
      name = machine |> Module.split() |> List.last() |> Macro.underscore()
      assert File.read!(Path.join(root, name <> ".md")) == machine.matrix()
      assert File.read!(Path.join(root, name <> ".mmd")) == machine.diagram()

      reachable =
        Enum.reduce(1..length(machine.states()), MapSet.new([hd(machine.states())]), fn _,
                                                                                        known ->
          Enum.reduce(machine.rows(), known, fn {from, _, _, to, _}, acc ->
            if MapSet.member?(known, from), do: MapSet.put(acc, to), else: acc
          end)
        end)

      assert reachable == MapSet.new(machine.states())

      for state <- machine.states(), event <- machine.events() do
        ctx = %{
          view: ImportState.initial(),
          snapshot: ImportState.initial(),
          payload: %{bytes_read: 10, total_bytes: 100, encounters_found: 1},
          error: nil,
          reason: :not_found
        }

        assert {:ok, next, _, _} = machine.step(state, event, ctx)
        assert next in machine.states()
      end

      assert machine.step(hd(machine.states()), :unknown, %{}) == :invalid
    end
  end

  test "random receipt/progress sequences cannot resurrect a terminal import or show an error while importing" do
    :rand.seed(:exsss, {818, 28, 329})
    now = ~U[2026-10-31 20:00:00Z]

    for _ <- 1..100 do
      Enum.reduce(1..100, ImportState.initial(), fn _, view ->
        receipt =
          Enum.random([
            nil,
            %{token: "one", path: "one", status: "importing", deadline: DateTime.add(now, 1)},
            %{token: "one", path: "one", status: "importing", deadline: now},
            %{token: "two", path: "two", status: "failed", error: "broken"},
            %{token: "two", path: "two", status: "failed", error: ":ingest_timeout"},
            %{token: "two", path: "two", status: "complete"}
          ])

        projected = ImportState.project(view, receipt, now)

        progressed =
          ImportState.progress(projected, %{
            bytes_read: Enum.random(-100..200),
            total_bytes: 100,
            encounters_found: 2
          })

        assert progressed.state == projected.state
        assert progressed.percent in 0..100
        assert progressed.error != nil == progressed.state in [:failed, :timed_out]
        if projected.state != :importing, do: assert(progressed == projected)

        if receipt && receipt.status == "importing" &&
             DateTime.compare(receipt.deadline, now) != :gt,
           do: assert(progressed.state == :timed_out)

        progressed
      end)
    end
  end

  test "a new operation token resets old progress and error" do
    now = DateTime.utc_now()

    previous = %{
      ImportState.initial()
      | state: :failed,
        token: "old",
        percent: 99,
        error: "old error"
    }

    next =
      ImportState.project(
        previous,
        %{token: "new", path: "new", status: "importing", deadline: DateTime.add(now, 60)},
        now
      )

    assert next.state == :importing
    assert next.percent == 0
    assert next.error == nil
  end

  test "random load sequences clear old errors on retry and ignore late terminal replies" do
    :rand.seed(:exsss, {78, 99, 100})

    Enum.reduce(1..1000, LoadState.initial(), fn _, status ->
      event = Enum.random(LoadState.events())

      {:ok, state, ctx, _} =
        LoadState.step(status.state, event, %{error: status.error, reason: :not_found})

      assert ctx.error != nil == (state == :failed)
      if status.state != :loading and event != :load, do: assert(state == status.state)
      %{state: state, error: ctx.error}
    end)
  end
end
