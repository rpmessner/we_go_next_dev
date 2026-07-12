defmodule WeGoNext.CombatLogFile do
  @moduledoc """
  Tracks combat log files and their parsing progress.
  Enables incremental parsing by remembering where we stopped.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.Accounts.User
  alias WeGoNext.Bronze.FileFingerprint

  @sources [:live, :warcraftlogs_archive]
  @archive_prefix "Archive-WoWCombatLog-"

  @doc """
  Returns the combat-log creation timestamp embedded in a live or archive filename.

  This is the canonical date for ordering logs. Filesystem modification and parse
  timestamps describe operational activity and must not change raid-night order.
  """
  def filename_datetime(path_or_filename) do
    filename = Path.basename(path_or_filename)

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

  schema "combat_log_files" do
    field(:file_path, :string)
    field(:file_size, :integer)
    field(:file_mtime, :utc_datetime)
    field(:last_parsed_byte, :integer, default: 0)
    field(:last_parsed_at, :utc_datetime)

    field(:source, Ecto.Enum,
      values: [live: "live", warcraftlogs_archive: "warcraftlogs_archive"],
      default: :live
    )

    field(:head_sha256, :string)
    field(:warcraft_logs_report_url, :string)
    field(:warcraft_logs_report_code, :string)
    field(:warcraft_logs_fight_id, :integer)
    field(:warcraft_logs_linked_at, :utc_datetime_usec)
    # Mark as complete when fully parsed and a newer log exists (dead log)
    field(:is_complete, :boolean, default: false)
    field(:watch_enabled, :boolean, default: false)
    field(:publish_enabled, :boolean, default: false)
    field(:raid_night_name, :string)

    belongs_to(:user, User)
    has_many(:encounters, WeGoNext.Encounters.Encounter)

    timestamps()
  end

  @doc false
  def changeset(combat_log_file, attrs) do
    combat_log_file
    |> cast(attrs, [
      :file_path,
      :file_size,
      :file_mtime,
      :last_parsed_byte,
      :last_parsed_at,
      :source,
      :head_sha256,
      :warcraft_logs_report_url,
      :warcraft_logs_report_code,
      :warcraft_logs_fight_id,
      :warcraft_logs_linked_at,
      :user_id,
      :is_complete,
      :watch_enabled,
      :publish_enabled,
      :raid_night_name
    ])
    |> validate_required([:file_path, :user_id, :source])
    |> validate_inclusion(:source, @sources)
    |> validate_format(:head_sha256, ~r/\A[0-9a-f]{64}\z/)
    |> unique_constraint(:file_path)
    |> check_constraint(:source, name: :combat_log_files_source_check)
  end

  def raid_night_name(%__MODULE__{raid_night_name: name, file_path: path}) do
    case String.trim(name || "") do
      "" -> default_raid_night_name(path)
      name -> name
    end
  end

  def default_raid_night_name(path) do
    case filename_datetime(path) do
      %NaiveDateTime{} = datetime -> "Raid Night — #{Calendar.strftime(datetime, "%b %d, %Y")}"
      nil -> "Raid Night"
    end
  end

  @doc """
  Updates the parsing progress after a successful parse.
  """
  def update_progress_changeset(combat_log_file, byte_offset) do
    combat_log_file
    |> cast(%{last_parsed_byte: byte_offset, last_parsed_at: DateTime.utc_now()}, [
      :last_parsed_byte,
      :last_parsed_at
    ])
  end

  @doc """
  Checks if the file has new content since last parse.
  Returns true if file size or mtime has changed.
  """
  def has_new_content?(%__MODULE__{} = clf) do
    case File.stat(clf.file_path) do
      {:ok, %{size: size, mtime: mtime}} ->
        mtime_dt = NaiveDateTime.from_erl!(mtime) |> DateTime.from_naive!("Etc/UTC")
        size > clf.file_size or DateTime.compare(mtime_dt, clf.file_mtime) == :gt

      {:error, _} ->
        false
    end
  end

  @doc """
  Checks if the log file has been partially imported (interrupted import).
  Returns true if we've started parsing but haven't reached the end of the file.
  """
  def partially_imported?(%__MODULE__{} = clf) do
    case File.stat(clf.file_path) do
      {:ok, %{size: disk_size}} ->
        parsed = clf.last_parsed_byte || 0
        # Partially imported if we've parsed something but not everything
        parsed > 0 and parsed < disk_size

      {:error, _} ->
        false
    end
  end

  @doc """
  Checks if the log file has been fully imported up to current disk size.
  """
  def fully_imported?(%__MODULE__{} = clf) do
    case File.stat(clf.file_path) do
      {:ok, %{size: disk_size}} ->
        parsed = clf.last_parsed_byte || 0
        parsed >= disk_size

      {:error, _} ->
        false
    end
  end

  @doc """
  Creates attrs from a file path by reading file metadata.
  """
  def attrs_from_file(file_path, user_id, opts \\ []) do
    source = Keyword.get(opts, :source, source_from_path(file_path))

    with {:ok, %{size: size, mtime: mtime}} <- File.stat(file_path),
         {:ok, head_sha256} <- FileFingerprint.head_sha256(file_path) do
      mtime_dt = NaiveDateTime.from_erl!(mtime) |> DateTime.from_naive!("Etc/UTC")

      {:ok,
       %{
         file_path: file_path,
         file_size: size,
         file_mtime: mtime_dt,
         source: source,
         head_sha256: head_sha256,
         user_id: user_id,
         last_parsed_byte: 0
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp source_from_path(file_path) do
    if file_path |> Path.basename() |> String.starts_with?(@archive_prefix) do
      :warcraftlogs_archive
    else
      :live
    end
  end
end
