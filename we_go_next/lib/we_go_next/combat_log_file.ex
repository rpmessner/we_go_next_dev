defmodule WeGoNext.CombatLogFile do
  @moduledoc """
  Tracks combat log files and their parsing progress.
  Enables incremental parsing by remembering where we stopped.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.Accounts.User

  schema "combat_log_files" do
    field :file_path, :string
    field :file_size, :integer
    field :file_mtime, :utc_datetime
    field :last_parsed_byte, :integer, default: 0
    field :last_parsed_at, :utc_datetime
    # Mark as complete when fully parsed and a newer log exists (dead log)
    field :is_complete, :boolean, default: false

    belongs_to :user, User
    has_many :encounters, WeGoNext.Encounters.Encounter

    timestamps()
  end

  @doc false
  def changeset(combat_log_file, attrs) do
    combat_log_file
    |> cast(attrs, [:file_path, :file_size, :file_mtime, :last_parsed_byte, :last_parsed_at, :user_id, :is_complete])
    |> validate_required([:file_path, :user_id])
    |> unique_constraint(:file_path)
  end

  @doc """
  Updates the parsing progress after a successful parse.
  """
  def update_progress_changeset(combat_log_file, byte_offset) do
    combat_log_file
    |> cast(%{last_parsed_byte: byte_offset, last_parsed_at: DateTime.utc_now()}, [:last_parsed_byte, :last_parsed_at])
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
  def attrs_from_file(file_path, user_id) do
    case File.stat(file_path) do
      {:ok, %{size: size, mtime: mtime}} ->
        mtime_dt = NaiveDateTime.from_erl!(mtime) |> DateTime.from_naive!("Etc/UTC")

        {:ok,
         %{
           file_path: file_path,
           file_size: size,
           file_mtime: mtime_dt,
           user_id: user_id,
           last_parsed_byte: 0
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
