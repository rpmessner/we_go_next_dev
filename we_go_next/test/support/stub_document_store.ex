defmodule WeGoNext.Support.StubDocumentStore do
  @moduledoc false

  defmacro __using__(table: table) do
    quote do
      @table unquote(table)

      def reset! do
        case :ets.whereis(@table) do
          :undefined -> :ok
          tid -> :ets.delete(tid)
        end

        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        :ok
      end

      def objects do
        ensure_table!()

        @table
        |> :ets.tab2list()
        |> Map.new(fn {key, body} -> {key, body} end)
      end

      @impl true
      def put(key, body) when is_binary(key) and is_binary(body) do
        ensure_table!()
        :ets.insert(@table, {key, body})
        :ok
      end

      @impl true
      def fetch(key) when is_binary(key) do
        ensure_table!()

        case :ets.lookup(@table, key) do
          [{^key, body}] -> {:ok, body}
          [] -> {:error, :enoent}
        end
      end

      @impl true
      def exists?(key) when is_binary(key) do
        ensure_table!()
        {:ok, :ets.member(@table, key)}
      end

      defp ensure_table! do
        case :ets.whereis(@table) do
          :undefined -> :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
          _tid -> :ok
        end
      end
    end
  end
end

defmodule WeGoNext.Support.StubSourceDocumentStore do
  @moduledoc false
  @behaviour WeGoNext.Documents.Store

  use WeGoNext.Support.StubDocumentStore, table: :wgn_stub_source_document_store
end

defmodule WeGoNext.Support.StubDestinationDocumentStore do
  @moduledoc false
  @behaviour WeGoNext.Documents.Store

  use WeGoNext.Support.StubDocumentStore, table: :wgn_stub_destination_document_store
end

defmodule WeGoNext.Support.FailingDestinationDocumentStore do
  @moduledoc false
  @behaviour WeGoNext.Documents.Store

  @impl true
  def put("index.json", _body), do: {:error, :index_failed}
  def put(key, body), do: WeGoNext.Support.StubDestinationDocumentStore.put(key, body)

  @impl true
  def fetch(key), do: WeGoNext.Support.StubDestinationDocumentStore.fetch(key)

  @impl true
  def exists?(key), do: WeGoNext.Support.StubDestinationDocumentStore.exists?(key)
end
