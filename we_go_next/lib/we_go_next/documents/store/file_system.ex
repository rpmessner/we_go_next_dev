defmodule WeGoNext.Documents.Store.FileSystem do
  @moduledoc """
  Filesystem-backed store for generated encounter documents.
  """

  @behaviour WeGoNext.Documents.Store

  @impl true
  def put(key, body) when is_binary(key) and is_binary(body) do
    path = path_for_key(key)

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, body)
    end
  end

  @impl true
  def fetch(key) when is_binary(key) do
    key
    |> path_for_key()
    |> File.read()
  end

  @impl true
  def exists?(key) when is_binary(key) do
    {:ok, File.exists?(path_for_key(key))}
  end

  def root do
    Application.fetch_env!(:we_go_next, :documents_root)
  end

  def path_for_key(key) when is_binary(key) do
    if unsafe_key?(key) do
      raise ArgumentError, "document store key must be a relative path without traversal"
    end

    Path.join(root(), key)
  end

  defp unsafe_key?(key) do
    Path.type(key) != :relative or String.split(key, "/") |> Enum.any?(&(&1 in ["", ".", ".."]))
  end
end
