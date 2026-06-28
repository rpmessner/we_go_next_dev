defmodule WeGoNextWeb.Plugs.PublicViewer do
  @moduledoc """
  Public report slug gate for public mirror viewer routes.
  """

  import Plug.Conn

  alias WeGoNext.Mirror.PublicReport
  alias WeGoNext.Repo

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case public_report(conn.path_params["slug"]) do
      %PublicReport{} = report ->
        conn
        |> put_session(:public_report_id, report.id)
        |> put_session(:public_report_slug, report.slug)
        |> put_session(:public_report_title, report.title)

      nil ->
        conn
        |> send_resp(:not_found, "Not Found")
        |> halt()
    end
  end

  defp public_report(slug) when is_binary(slug),
    do: Repo.get_by(PublicReport, slug: slug, enabled: true)

  defp public_report(_slug), do: nil
end
