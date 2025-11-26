defmodule CombatLogParser.EncounterStore do
  @moduledoc """
  Stores parsed encounters in ETS for quick access by the web UI.
  """
  use GenServer

  @table_name :encounter_store

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Loads encounters from a combat log file.
  Returns {:ok, count} on success, {:error, reason} on failure.
  """
  def load_log(log_path) do
    GenServer.call(__MODULE__, {:load_log, log_path}, :infinity)
  end

  @doc """
  Returns all loaded encounters.
  """
  def list_encounters do
    case :ets.lookup(@table_name, :encounters) do
      [{:encounters, encounters}] -> encounters
      [] -> []
    end
  end

  @doc """
  Returns a single encounter by index (1-based).
  """
  def get_encounter(index) when is_integer(index) do
    encounters = list_encounters()
    Enum.at(encounters, index - 1)
  end

  @doc """
  Returns the currently loaded log path.
  """
  def current_log_path do
    case :ets.lookup(@table_name, :log_path) do
      [{:log_path, path}] -> path
      [] -> nil
    end
  end

  @doc """
  Clears all stored encounters.
  """
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:load_log, log_path}, _from, state) do
    case CombatLogParser.parse(log_path) do
      {:ok, encounters} ->
        :ets.insert(@table_name, {:encounters, encounters})
        :ets.insert(@table_name, {:log_path, log_path})

        # Broadcast that encounters were loaded
        Phoenix.PubSub.broadcast(
          CombatLogParser.PubSub,
          "encounters",
          {:encounters_loaded, length(encounters)}
        )

        {:reply, {:ok, length(encounters)}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete(@table_name, :encounters)
    :ets.delete(@table_name, :log_path)
    {:reply, :ok, state}
  end
end
