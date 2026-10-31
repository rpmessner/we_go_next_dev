defmodule WeGoNextWeb.WatchControl do
  @moduledoc "Shared watch-machine adapter; persisted flags alone are not a live watch snapshot."
  use Phoenix.Component
  alias WeGoNext.{CombatLogFile, FileWatcher, Repo}
  import Phoenix.LiveView, only: [put_flash: 3]

  def subscribe, do: Phoenix.PubSub.subscribe(WeGoNext.PubSub, "encounters")
  def current_file, do: FileWatcher.current_file()

  def snapshot(logs) do
    watched = current_file()
    Enum.map(logs, &Map.put(&1, :watch_enabled, not is_nil(watched) and &1.id == watched.id))
  end

  def toggle(socket, file_id) do
    with {id, ""} <- Integer.parse(to_string(file_id)),
         %CombatLogFile{source: :live} = file <-
           Repo.get_by(CombatLogFile, id: id, user_id: socket.assigns.user.id),
         :ok <- change(file) do
      socket
    else
      _ -> put_flash(socket, :error, "Failed to update watch setting")
    end
  end

  defp change(file) do
    case current_file() do
      %CombatLogFile{id: id} when id == file.id -> FileWatcher.stop_watching(file)
      _ -> FileWatcher.watch(file)
    end
  end

  attr(:file, :map, required: true)
  attr(:id, :string, required: true)
  attr(:label, :string, default: "Watch")
  attr(:class, :string, default: "")
  attr(:variant, :atom, default: :checkbox)

  def render(assigns) do
    ~H"""
    <button :if={@variant == :clear} phx-click="toggle_watch_enabled"
      phx-value-file_id={@file.id} class={@class}>Clear</button>
    <label :if={@variant == :checkbox} class={@class}>
      <input id={@id} type="checkbox" checked={@file.watch_enabled}
        phx-click="toggle_watch_enabled" phx-value-file_id={@file.id}
        class="rounded border-zinc-600 bg-zinc-900 text-wow-gold focus:ring-wow-gold" />
      {@label}
    </label>
    """
  end
end
