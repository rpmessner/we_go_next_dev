defmodule WeGoNext.Documents.Store.R2 do
  @moduledoc """
  S3-compatible Cloudflare R2 store for generated encounter documents.
  """

  @behaviour WeGoNext.Documents.Store

  alias WeGoNext.Accounts

  @impl true
  def put(key, body) when is_binary(key) and is_binary(body) do
    with {:ok, config} <- config(),
         {:ok, response} <-
           Req.put(req(config), url: url(config.bucket, key), body: body, headers: json_headers()),
         {:ok, :ok} <- success_response(response, :ok) do
      :ok
    end
  end

  @impl true
  def fetch(key) when is_binary(key) do
    with {:ok, config} <- config(),
         {:ok, response} <- Req.get(req(config), url: url(config.bucket, key), decode_body: false) do
      success_response(response, response.body)
    end
  end

  @impl true
  def exists?(key) when is_binary(key) do
    with {:ok, config} <- config(),
         {:ok, response} <- Req.head(req(config), url: url(config.bucket, key)) do
      case response.status do
        status when status in 200..299 -> {:ok, true}
        404 -> {:ok, false}
        status -> {:error, {:http_error, status, response.body}}
      end
    end
  end

  def config do
    case Application.get_env(:we_go_next, :documents_r2) do
      nil -> account_config(WeGoNext.mode())
      config -> normalize_config(config)
    end
  end

  defp account_config(:public), do: {:error, :r2_not_configured}

  defp account_config(:parser) do
    user = Accounts.get_or_create_default_user()

    with true <- Accounts.document_r2_configured?(user),
         {:ok, secret_access_key} <- Accounts.document_r2_secret_access_key(user) do
      normalize_config(%{
        endpoint: user.document_r2_endpoint,
        bucket: user.document_r2_bucket,
        access_key_id: user.document_r2_access_key_id,
        secret_access_key: secret_access_key
      })
    else
      false -> {:error, :r2_not_configured}
      :error -> {:error, :r2_not_configured}
    end
  end

  defp normalize_config(config) do
    config = Map.new(config)

    with {:ok, endpoint} <- fetch_required(config, :endpoint),
         {:ok, bucket} <- fetch_required(config, :bucket),
         {:ok, access_key_id} <- fetch_required(config, :access_key_id),
         {:ok, secret_access_key} <- fetch_required(config, :secret_access_key) do
      {:ok,
       %{
         endpoint: endpoint,
         bucket: bucket,
         access_key_id: access_key_id,
         secret_access_key: secret_access_key,
         req_options: Map.get(config, :req_options, [])
       }}
    end
  end

  defp fetch_required(config, key) do
    case config |> Map.get(key) |> trim_or_nil() do
      nil -> {:error, {:missing_r2_config, key}}
      value -> {:ok, value}
    end
  end

  defp req(config) do
    config.req_options
    |> Req.new()
    |> ReqS3.attach(
      aws_sigv4: [
        access_key_id: config.access_key_id,
        secret_access_key: config.secret_access_key,
        region: "auto",
        service: "s3"
      ],
      aws_endpoint_url_s3: config.endpoint
    )
  end

  defp url(bucket, key), do: "s3://#{bucket}/#{key}"

  defp json_headers, do: [{"content-type", "application/json"}]

  defp success_response(%Req.Response{status: status, body: body}, value)
       when status in 200..299 do
    {:ok, value || body}
  end

  defp success_response(%Req.Response{status: status, body: body}, _value),
    do: {:error, {:http_error, status, body}}

  defp trim_or_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp trim_or_nil(value), do: value
end
