defmodule WeGoNext.Accounts do
  @moduledoc """
  The Accounts context - manages users and their settings.
  """

  require Logger

  alias WeGoNext.{CombatLogFile, FileWatcher, Repo}
  alias WeGoNext.Accounts.SecretBox
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
  Stores Warcraft Logs credentials for local API usage.

  The API key is encrypted before persistence and should never be logged or
  rendered back to the browser.
  """
  def set_warcraft_logs_credentials(%User{} = user, client_name, api_key) do
    client_name = trim_or_nil(client_name)
    api_key = trim_or_nil(api_key)

    cond do
      is_nil(client_name) ->
        {:error, :client_name_required}

      is_nil(api_key) ->
        {:error, :api_key_required}

      true ->
        with {:ok, encrypted_api_key} <- SecretBox.encrypt(api_key) do
          update_user_settings(user, %{
            warcraft_logs_client_name: client_name,
            warcraft_logs_api_key_encrypted: encrypted_api_key,
            warcraft_logs_api_key_set_at: DateTime.utc_now()
          })
        end
    end
  end

  @doc """
  Updates the saved Warcraft Logs client name without replacing the saved key.
  """
  def update_warcraft_logs_client_name(%User{} = user, client_name) do
    case trim_or_nil(client_name) do
      nil -> {:error, :client_name_required}
      client_name -> update_user_settings(user, %{warcraft_logs_client_name: client_name})
    end
  end

  def clear_warcraft_logs_credentials(%User{} = user) do
    update_user_settings(user, %{
      warcraft_logs_client_name: nil,
      warcraft_logs_api_key_encrypted: nil,
      warcraft_logs_api_key_set_at: nil
    })
  end

  def warcraft_logs_api_key(%User{warcraft_logs_api_key_encrypted: encrypted})
      when is_binary(encrypted) do
    SecretBox.decrypt(encrypted)
  end

  def warcraft_logs_api_key(%User{}), do: :error

  def warcraft_logs_credentials_configured?(%User{} = user) do
    is_binary(user.warcraft_logs_client_name) and is_binary(user.warcraft_logs_api_key_encrypted)
  end

  @doc """
  Stores public mirror upload settings for the local parser.
  """
  def set_mirror_upload_settings(%User{} = user, public_base_url, ingest_token) do
    public_base_url = trim_or_nil(public_base_url)
    ingest_token = trim_or_nil(ingest_token)

    cond do
      is_nil(public_base_url) ->
        {:error, :public_base_url_required}

      is_nil(ingest_token) ->
        {:error, :ingest_token_required}

      true ->
        with {:ok, encrypted_token} <- SecretBox.encrypt(ingest_token) do
          update_user_settings(user, %{
            mirror_public_base_url: public_base_url,
            mirror_ingest_token_encrypted: encrypted_token,
            mirror_ingest_token_set_at: DateTime.utc_now()
          })
        end
    end
  end

  def clear_mirror_upload_settings(%User{} = user) do
    update_user_settings(user, %{
      mirror_public_base_url: nil,
      mirror_ingest_token_encrypted: nil,
      mirror_ingest_token_set_at: nil
    })
  end

  def mirror_ingest_token(%User{mirror_ingest_token_encrypted: encrypted})
      when is_binary(encrypted) do
    SecretBox.decrypt(encrypted)
  end

  def mirror_ingest_token(%User{}), do: :error

  def mirror_upload_configured?(%User{} = user) do
    is_binary(user.mirror_public_base_url) and is_binary(user.mirror_ingest_token_encrypted)
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
          |> Enum.sort_by(&log_sort_datetime/1, {:desc, NaiveDateTime})

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
      filename_datetime: filename_datetime(filename),
      modified: modified_ndt,
      source: source
    }
  end

  defp log_sort_datetime(%{filename_datetime: %NaiveDateTime{} = filename_datetime}),
    do: filename_datetime

  defp log_sort_datetime(%{modified: %NaiveDateTime{} = modified}), do: modified

  defp filename_datetime(filename) do
    case Regex.run(
           ~r/^(?:Archive-)?WoWCombatLog-(\d{2})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})\.txt$/,
           filename
         ) do
      [_, month, day, year, hour, minute, second] ->
        with {month, ""} <- Integer.parse(month),
             {day, ""} <- Integer.parse(day),
             {year, ""} <- Integer.parse(year),
             {hour, ""} <- Integer.parse(hour),
             {minute, ""} <- Integer.parse(minute),
             {second, ""} <- Integer.parse(second),
             {:ok, datetime} <-
               NaiveDateTime.new(2000 + year, month, day, hour, minute, second) do
          datetime
        else
          _ -> nil
        end

      _ ->
        nil
    end
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
      {:ok, %CombatLogFile{} = combat_log_file} ->
        FileWatcher.refresh_if_tracking(combat_log_file)
        :ok

      {:ok, nil} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to reconcile archived combat log #{full_path}: #{inspect(reason)}")

        :ok
    end
  end

  defp maybe_reconcile_archive_move(_full_path, _source, _user), do: :ok

  defp trim_or_nil(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trim_or_nil(_value), do: nil
end
