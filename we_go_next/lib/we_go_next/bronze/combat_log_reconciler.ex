defmodule WeGoNext.Bronze.CombatLogReconciler do
  @moduledoc """
  Reconciles combat log file rows when live logs are moved into Warcraft Logs archive.
  """

  import Ecto.Query
  require Logger

  alias WeGoNext.Accounts.User
  alias WeGoNext.{CombatLogFile, Repo}

  @live_prefix "WoWCombatLog-"
  @archive_prefix "Archive-WoWCombatLog-"

  @doc """
  Updates an existing live row when `archive_path` is the archived copy of that log.

  Returns `{:ok, combat_log_file}` when a row was reconciled, `{:ok, nil}` when no
  matching live row exists, and `{:error, reason}` when archive metadata cannot be read.
  """
  def reconcile_archive_move(archive_path, user_id)
      when is_binary(archive_path) and not is_nil(user_id) do
    with {:archive, true} <- {:archive, archive_path?(archive_path)},
         {:ok, archive_attrs} <-
           CombatLogFile.attrs_from_file(archive_path, user_id, source: :warcraftlogs_archive) do
      archive_path
      |> matching_live_file(user_id, archive_attrs)
      |> update_live_file(archive_attrs)
    else
      {:archive, false} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  def reconcile_archive_move(_archive_path, _user_id), do: {:ok, nil}

  @doc """
  Attempts to find an archived replacement for a missing live combat log row.
  """
  def reconcile_missing_file(%CombatLogFile{source: :live} = combat_log_file) do
    with {:ok, :missing} <- missing_file(combat_log_file.file_path),
         %User{wow_logs_path: base_path} when is_binary(base_path) <-
           Repo.get(User, combat_log_file.user_id),
         archive_path <- archive_path_for(base_path, combat_log_file.file_path),
         true <- File.regular?(archive_path) do
      reconcile_archive_move(archive_path, combat_log_file.user_id)
    else
      {:ok, :present} -> {:ok, combat_log_file}
      _ -> {:ok, nil}
    end
  end

  def reconcile_missing_file(%CombatLogFile{}), do: {:ok, nil}

  defp matching_live_file(archive_path, user_id, archive_attrs) do
    archive_suffix = archive_suffix(archive_path)

    CombatLogFile
    |> where([clf], clf.user_id == ^user_id)
    |> where([clf], clf.source == :live)
    |> Repo.all()
    |> Enum.filter(&(live_suffix(&1.file_path) == archive_suffix))
    |> Enum.filter(&(archive_attrs.file_size >= recorded_size(&1)))
    |> Enum.find(&fingerprint_match?(&1, archive_attrs, archive_path))
  end

  defp update_live_file(nil, _archive_attrs), do: {:ok, nil}

  defp update_live_file(%CombatLogFile{} = combat_log_file, archive_attrs) do
    combat_log_file
    |> Ecto.Changeset.change(%{
      file_path: archive_attrs.file_path,
      file_size: archive_attrs.file_size,
      file_mtime: archive_attrs.file_mtime,
      source: :warcraftlogs_archive,
      head_sha256: archive_attrs.head_sha256
    })
    |> Repo.update()
  end

  defp fingerprint_match?(%CombatLogFile{head_sha256: hash}, archive_attrs, _archive_path)
       when is_binary(hash) do
    hash == archive_attrs.head_sha256
  end

  defp fingerprint_match?(%CombatLogFile{} = combat_log_file, _archive_attrs, archive_path) do
    Logger.warning(
      "Reconciling archived combat log #{archive_path} to live row #{combat_log_file.id} without head_sha256"
    )

    true
  end

  defp archive_path?(path), do: path |> Path.basename() |> String.starts_with?(@archive_prefix)

  defp archive_suffix(path) do
    path
    |> Path.basename()
    |> String.replace_prefix(@archive_prefix, "")
  end

  defp live_suffix(path) do
    path
    |> Path.basename()
    |> String.replace_prefix(@live_prefix, "")
  end

  defp recorded_size(%CombatLogFile{file_size: size}) when is_integer(size), do: size
  defp recorded_size(_combat_log_file), do: 0

  defp missing_file(file_path) do
    if File.regular?(file_path), do: {:ok, :present}, else: {:ok, :missing}
  end

  defp archive_path_for(base_path, live_path) do
    archive_name =
      live_path
      |> Path.basename()
      |> String.replace_prefix(@live_prefix, @archive_prefix)

    Path.join([base_path, "warcraftlogsarchive", archive_name])
  end
end
