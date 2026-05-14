defmodule WeGoNext.Accounts do
  @moduledoc """
  The Accounts context - manages users and their settings.
  """

  alias WeGoNext.Repo
  alias WeGoNext.Accounts.User

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

  def list_combat_logs(%User{wow_logs_path: path}) do
    list_combat_logs_in_path(path)
  end

  def list_combat_logs_in_path(path) do
    case File.ls(path) do
      {:ok, files} ->
        logs =
          files
          |> Enum.filter(fn f ->
            String.starts_with?(f, "WoWCombatLog") and String.ends_with?(f, ".txt")
          end)
          |> Enum.map(fn filename ->
            full_path = Path.join(path, filename)
            stat = File.stat!(full_path)

            # Convert erlang datetime tuple to NaiveDateTime for sorting
            modified_ndt = NaiveDateTime.from_erl!(stat.mtime)

            %{
              filename: filename,
              full_path: full_path,
              size: stat.size,
              modified: modified_ndt
            }
          end)
          |> Enum.sort_by(& &1.modified, {:desc, NaiveDateTime})

        {:ok, logs}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
