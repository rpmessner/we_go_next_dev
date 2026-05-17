defmodule WeGoNext.Accounts do
  @moduledoc """
  The Accounts context - manages users and their settings.
  """

  require Logger

  alias WeGoNext.{CombatLogFile, Repo}
  alias WeGoNext.Accounts.User
  alias WeGoNext.Bronze.{CombatLogReconciler, FileFingerprint}

  @log_sources [
    %{source: :live, directory: nil, prefix: "WoWCombatLog-"},
    %{
      source: :warcraftlogs_archive,
      directory: "warcraftlogsarchive",
      prefix: "Archive-WoWCombatLog-"
    }
  ]

  @doc """
  Gets the default user, creating one if it doesn't exist.
  """
  @default_wow_logs_path "/mnt/g/World of Warcraft/_retail_/Logs"

  def get_or_create_default_user do
    case Repo.get_by(User, name: "default") do
      nil ->
        %User{name: "default", wow_logs_path: @default_wow_logs_path}
        |> Repo.insert!()

      %User{wow_logs_path: nil} = user ->
        # Existing user without path - set the default
        {:ok, user} = set_wow_logs_path(user, @default_wow_logs_path)
        user

      user ->
        user
    end
  end

  @doc """
  Gets a user by ID.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Updates a user's settings.
  """
  def update_user_settings(%User{} = user, attrs) do
    user
    |> User.settings_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates the WoW logs path for a user.
  """
  def set_wow_logs_path(%User{} = user, path) do
    update_user_settings(user, %{wow_logs_path: path})
  end

  @doc """
  Updates the character name for a user.
  """
  def set_character_name(%User{} = user, name) do
    update_user_settings(user, %{character_name: name})
  end

  @doc """
  Updates the last loaded log for a user.
  """
  def set_last_loaded_log(%User{} = user, log_path) do
    update_user_settings(user, %{last_loaded_log: log_path})
  end

  @doc """
  Lists available combat log files in the user's configured WoW logs directory.
  Returns {:ok, files} or {:error, reason}.
  """
  def list_combat_logs(%User{wow_logs_path: nil}), do: {:error, :no_path_configured}

  def list_combat_logs(%User{wow_logs_path: path} = user) do
    list_combat_logs_in_path(path, user)
  end

  def list_combat_logs_in_path(path), do: list_combat_logs_in_path(path, nil)

  def list_combat_logs_in_path(path, user) do
    case File.ls(path) do
      {:ok, _files} ->
        logs =
          @log_sources
          |> Enum.flat_map(&list_logs_for_source(path, &1, user))
          |> Enum.sort_by(& &1.modified, {:desc, NaiveDateTime})

        {:ok, logs}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_logs_for_source(
         base_path,
         %{source: source, directory: directory, prefix: prefix},
         user
       ) do
    directory_path = if directory, do: Path.join(base_path, directory), else: base_path

    case File.ls(directory_path) do
      {:ok, files} ->
        files
        |> Enum.filter(&combat_log_filename?(&1, prefix))
        |> Enum.map(&log_entry(directory_path, &1, source, user))

      {:error, :enoent} when directory != nil ->
        []

      {:error, reason} ->
        Logger.warning("Failed to list combat logs in #{directory_path}: #{inspect(reason)}")
        []
    end
  end

  defp combat_log_filename?(filename, prefix) do
    String.starts_with?(filename, prefix) and String.ends_with?(filename, ".txt")
  end

  defp log_entry(directory_path, filename, source, user) do
    full_path = Path.join(directory_path, filename)
    stat = File.stat!(full_path)
    maybe_reconcile_archive_move(full_path, source, user)
    maybe_backfill_head_sha256(full_path, user)

    # Convert erlang datetime tuple to NaiveDateTime for sorting
    modified_ndt = NaiveDateTime.from_erl!(stat.mtime)

    %{
      filename: filename,
      full_path: full_path,
      size: stat.size,
      modified: modified_ndt,
      source: source
    }
  end

  defp maybe_backfill_head_sha256(_full_path, nil), do: :ok

  defp maybe_backfill_head_sha256(full_path, %User{id: user_id}) do
    case Repo.get_by(CombatLogFile, file_path: full_path, user_id: user_id) do
      %CombatLogFile{head_sha256: nil} = combat_log_file ->
        case FileFingerprint.head_sha256(full_path) do
          {:ok, head_sha256} ->
            combat_log_file
            |> Ecto.Changeset.change(%{head_sha256: head_sha256})
            |> Repo.update()

            :ok

          {:error, reason} ->
            Logger.warning(
              "Failed to backfill combat log fingerprint for #{full_path}: #{inspect(reason)}"
            )

            :ok
        end

      _ ->
        :ok
    end
  end

  defp maybe_reconcile_archive_move(full_path, :warcraftlogs_archive, %User{id: user_id}) do
    case CombatLogReconciler.reconcile_archive_move(full_path, user_id) do
      {:ok, _combat_log_file_or_nil} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to reconcile archived combat log #{full_path}: #{inspect(reason)}")

        :ok
    end
  end

  defp maybe_reconcile_archive_move(_full_path, _source, _user), do: :ok
end
