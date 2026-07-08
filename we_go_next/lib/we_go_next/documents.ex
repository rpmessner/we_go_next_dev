defmodule WeGoNext.Documents do
  @moduledoc """
  Builds and persists JSON encounter documents for the frontend render path.
  """

  import Ecto.Query

  alias WeGoNext.Documents.{EncounterDocument, Store}
  alias WeGoNext.Gold.DimEncounter
  alias WeGoNext.Repo

  @type generate_result :: %{
          source_encounter_key: String.t(),
          encounter_path: String.t(),
          index_path: String.t()
        }

  @doc """
  Generates and writes one encounter document, then refreshes `index.json`.
  """
  @spec generate_for_encounter(pos_integer() | DimEncounter.t(), keyword()) ::
          {:ok, generate_result()} | {:error, term()}
  def generate_for_encounter(encounter_or_id, opts \\ [])

  def generate_for_encounter(%DimEncounter{id: id}, opts), do: generate_for_encounter(id, opts)

  def generate_for_encounter(encounter_dim_id, opts)
      when is_integer(encounter_dim_id) and is_list(opts) do
    with {:ok, document} <- EncounterDocument.encode(encounter_dim_id, opts),
         {:ok, encounter_path} <- Store.FileSystem.put_encounter(document),
         {:ok, index_path} <- Store.FileSystem.refresh_index() do
      {:ok,
       %{
         source_encounter_key: document.source_encounter_key,
         encounter_path: encounter_path,
         index_path: index_path
       }}
    end
  end

  @doc """
  Generates documents for every known gold encounter.
  """
  @spec rebuild_all(keyword()) :: {:ok, %{encounters: non_neg_integer()}} | {:error, map()}
  def rebuild_all(opts \\ []) do
    rebuild_encounters(encounter_ids(opts), opts)
  end

  @doc """
  Generates documents for the given gold encounter ids.
  """
  @spec rebuild_encounters([pos_integer()], keyword()) ::
          {:ok, %{encounters: non_neg_integer()}} | {:error, map()}
  def rebuild_encounters(encounter_ids, opts \\ []) when is_list(encounter_ids) do
    totals = %{encounters: 0}

    Enum.reduce_while(encounter_ids, {:ok, totals}, fn encounter_id, {:ok, totals} ->
      case generate_for_encounter(encounter_id, opts) do
        {:ok, _result} ->
          {:cont, {:ok, %{totals | encounters: totals.encounters + 1}}}

        {:error, reason} ->
          {:halt, {:error, %{encounter_id: encounter_id, reason: reason, totals: totals}}}
      end
    end)
  end

  defp encounter_ids(opts) do
    query =
      DimEncounter
      |> order_by([encounter], asc: encounter.id)
      |> select([encounter], encounter.id)

    case Keyword.fetch(opts, :encounter_id) do
      {:ok, encounter_id} -> [encounter_id]
      :error -> Repo.all(query)
    end
  end
end
