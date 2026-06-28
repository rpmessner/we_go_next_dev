defmodule WeGoNext.Mirror.Upload do
  @moduledoc """
  HTTP client for publishing gold snapshots to the hosted public mirror.
  """

  alias WeGoNext.{Accounts, Repo}
  alias WeGoNext.Gold.DimEncounter
  alias WeGoNext.Mirror.Snapshot

  @spec publish(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def publish(source_encounter_key, opts \\ []) when is_binary(source_encounter_key) do
    with {:ok, config} <- upload_config(opts),
         %DimEncounter{id: encounter_dim_id} <-
           Repo.get_by(DimEncounter, source_encounter_key: source_encounter_key),
         {:ok, snapshot} <- Snapshot.encode_encounter_snapshot(encounter_dim_id),
         {:ok, response} <- post_snapshot(config, snapshot, opts),
         :ok <- success_response(response) do
      {:ok, response}
    else
      nil -> {:error, :encounter_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp upload_config(opts) do
    case Keyword.get(opts, :config) do
      %{public_base_url: base_url, ingest_token: token}
      when is_binary(base_url) and is_binary(token) ->
        {:ok, %{public_base_url: base_url, ingest_token: token}}

      nil ->
        default_upload_config()

      _config ->
        {:error, :invalid_upload_config}
    end
  end

  defp default_upload_config do
    user = Accounts.get_or_create_default_user()

    with true <- Accounts.mirror_upload_configured?(user),
         {:ok, token} <- Accounts.mirror_ingest_token(user) do
      {:ok, %{public_base_url: user.mirror_public_base_url, ingest_token: token}}
    else
      false -> {:error, :mirror_upload_not_configured}
      :error -> {:error, :mirror_upload_not_configured}
    end
  end

  defp post_snapshot(config, snapshot, opts) do
    url =
      config.public_base_url
      |> String.trim_trailing("/")
      |> Kernel.<>("/api/ingest")

    if post_fun = Keyword.get(opts, :post_fun) do
      post_fun.(url, snapshot, config.ingest_token)
    else
      Req.post(url,
        json: snapshot,
        headers: [{"authorization", "Bearer #{config.ingest_token}"}],
        receive_timeout: Keyword.get(opts, :receive_timeout, 15_000)
      )
    end
  end

  defp success_response(%Req.Response{status: status}) when status in 200..299, do: :ok

  defp success_response(%Req.Response{status: status, body: body}),
    do: {:error, {:http_error, status, body}}

  defp success_response(%{status: status}) when status in 200..299, do: :ok
  defp success_response(%{status: status, body: body}), do: {:error, {:http_error, status, body}}
  defp success_response(_response), do: :ok
end
