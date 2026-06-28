defmodule WeGoNext.Mirror.Outbox do
  @moduledoc """
  Coalesced parser-side outbox for public mirror uploads.
  """

  import Ecto.Query

  alias WeGoNext.Gold.DimEncounter
  alias WeGoNext.Mirror.{MirrorUpload, Upload}
  alias WeGoNext.Repo

  @doc """
  Enqueues publish intent for a gold encounter after a successful rebuild.
  """
  @spec enqueue_for_encounter(pos_integer() | DimEncounter.t()) ::
          {:ok, MirrorUpload.t()} | {:error, term()}
  def enqueue_for_encounter(%DimEncounter{id: id}), do: enqueue_for_encounter(id)

  def enqueue_for_encounter(encounter_dim_id) when is_integer(encounter_dim_id) do
    case Repo.get(DimEncounter, encounter_dim_id) do
      %DimEncounter{source_encounter_key: key} when is_binary(key) ->
        enqueue(key)

      %DimEncounter{} ->
        {:error, :missing_source_encounter_key}

      nil ->
        {:error, :encounter_not_found}
    end
  end

  @doc """
  Coalesces publish intent by source encounter key.
  """
  @spec enqueue(String.t()) :: {:ok, MirrorUpload.t()} | {:error, Ecto.Changeset.t()}
  def enqueue(source_encounter_key) when is_binary(source_encounter_key) do
    now = DateTime.utc_now()

    Repo.insert_all(
      MirrorUpload,
      [
        %{
          source_encounter_key: source_encounter_key,
          state: "pending",
          last_error: nil,
          published_at: nil,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: [
        set: [
          state: "stale",
          last_error: nil,
          published_at: nil,
          updated_at: now
        ]
      ],
      conflict_target: [:source_encounter_key]
    )

    {:ok, Repo.get_by!(MirrorUpload, source_encounter_key: source_encounter_key)}
  end

  @doc """
  Processes a bounded batch of pending/stale/error upload rows.
  """
  @spec process_pending(keyword()) :: %{published: non_neg_integer(), error: non_neg_integer()}
  def process_pending(opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    publish_opts = Keyword.drop(opts, [:limit])

    MirrorUpload
    |> where([upload], upload.state in ["pending", "stale", "error"])
    |> order_by([upload], asc: upload.updated_at, asc: upload.id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.reduce(%{published: 0, error: 0}, fn upload, totals ->
      case publish_upload(upload, publish_opts) do
        {:ok, _upload} -> %{totals | published: totals.published + 1}
        {:error, _upload} -> %{totals | error: totals.error + 1}
      end
    end)
  end

  defp publish_upload(%MirrorUpload{} = upload, opts) do
    case Upload.publish(upload.source_encounter_key, opts) do
      {:ok, _response} ->
        {:ok,
         update_upload!(upload, %{
           state: "published",
           last_error: nil,
           published_at: DateTime.utc_now()
         })}

      {:error, reason} ->
        {:error,
         update_upload!(upload, %{
           state: "error",
           last_error: inspect(reason)
         })}
    end
  end

  defp update_upload!(%MirrorUpload{} = upload, attrs) do
    attrs =
      Map.merge(attrs, %{
        attempt_count: upload.attempt_count + 1,
        last_attempted_at: DateTime.utc_now()
      })

    upload
    |> MirrorUpload.changeset(attrs)
    |> Repo.update!()
  end
end
