defmodule WeGoNextWeb.ImportStatus do
  @moduledoc "LiveView adapter for receipt reconciliation, including missed completion notifications."
  import Phoenix.Component, only: [assign: 3]
  alias WeGoNext.{ImportWorker, Repo}
  alias WeGoNext.FileIngest.Operation
  alias WeGoNextWeb.ImportState

  def mount(socket, user_id) do
    if Phoenix.LiveView.connected?(socket),
      do: Phoenix.PubSub.subscribe(WeGoNext.PubSub, ImportWorker.progress_topic(user_id))

    socket
    |> assign(:import_status, ImportState.initial())
    |> assign(:import_timer, nil)
    |> refresh(user_id)
  end

  def refresh(socket, user_id) do
    if socket.assigns.import_timer, do: Process.cancel_timer(socket.assigns.import_timer)
    receipt = Repo.get_by(Operation, user_id: user_id)
    status = ImportState.project(socket.assigns.import_status, receipt, DateTime.utc_now())

    timer =
      if Phoenix.LiveView.connected?(socket) and status.state == :importing,
        do: Process.send_after(self(), :reconcile_import, 1_000)

    socket |> assign(:import_status, status) |> assign(:import_timer, timer)
  end

  def progress(socket, payload) do
    assign(socket, :import_status, ImportState.progress(socket.assigns.import_status, payload))
  end
end
