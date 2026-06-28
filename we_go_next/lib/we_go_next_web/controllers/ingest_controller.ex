defmodule WeGoNextWeb.IngestController do
  use WeGoNextWeb, :controller

  alias WeGoNext.Mirror.Ingest

  def create(%{path_params: %{"slug" => slug}} = conn, params) do
    with :ok <- authorize(conn),
         {:ok, result} <- Ingest.upsert_snapshot(slug, params) do
      json(conn, %{
        status: "ok",
        report_slug: result.public_report.slug,
        source_encounter_key: result.encounter.source_encounter_key,
        deleted: result.deleted,
        inserted: result.inserted
      })
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})

      {:error, {:unsupported_schema_version, _version}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "unsupported_schema_version"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_snapshot", reason: inspect(reason)})
    end
  end

  defp authorize(conn) do
    expected = Application.get_env(:we_go_next, :mirror_ingest_token)

    with token when is_binary(token) <- bearer_token(conn),
         expected when is_binary(expected) <- expected,
         true <- secure_compare(token, expected) do
      :ok
    else
      _other -> {:error, :unauthorized}
    end
  end

  defp bearer_token(conn) do
    conn
    |> get_req_header("authorization")
    |> List.first()
    |> case do
      "Bearer " <> token -> token
      _other -> nil
    end
  end

  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    Plug.Crypto.secure_compare(left, right)
  end

  defp secure_compare(_left, _right), do: false
end
