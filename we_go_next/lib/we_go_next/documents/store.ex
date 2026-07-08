defmodule WeGoNext.Documents.Store do
  @moduledoc """
  Storage behaviour for generated encounter documents.
  """

  @type key :: String.t()
  @type body :: binary()

  @callback put(key(), body()) :: :ok | {:error, term()}
  @callback fetch(key()) :: {:ok, body()} | {:error, term()}
  @callback exists?(key()) :: {:ok, boolean()} | {:error, term()}

  def configured_module(opts \\ []) do
    Keyword.get(opts, :store) ||
      Application.get_env(:we_go_next, :documents_store, WeGoNext.Documents.Store.FileSystem)
  end
end
