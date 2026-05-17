defmodule WeGoNext.Bronze.FileFingerprint do
  @moduledoc """
  Small file fingerprints used to recognize moved combat logs cheaply.
  """

  @head_bytes 4_096

  @doc """
  Returns the SHA-256 digest of the first 4 KB of a file as lowercase hex.
  """
  def head_sha256(file_path) when is_binary(file_path) do
    case File.open(file_path, [:read], fn file ->
           case IO.binread(file, @head_bytes) do
             data when is_binary(data) -> {:ok, digest(data)}
             :eof -> {:ok, digest("")}
             {:error, reason} -> {:error, reason}
           end
         end) do
      {:ok, {:ok, hash}} -> {:ok, hash}
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp digest(data) do
    :sha256
    |> :crypto.hash(data)
    |> Base.encode16(case: :lower)
  end
end
