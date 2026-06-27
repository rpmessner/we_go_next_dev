defmodule WeGoNext.WarcraftLogs do
  @moduledoc """
  Local helpers for associating Warcraft Logs reports with imported combat logs.
  """

  import Ecto.Changeset

  alias WeGoNext.{CombatLogFile, Repo}

  @report_path ~r{/reports/([^/?#]+)}

  @doc """
  Parses a Warcraft Logs report URL into report identity.
  """
  def parse_report_url(url) when is_binary(url) do
    url = String.trim(url)

    with {:ok, uri} <- URI.new(url),
         {:ok, report_code} <- report_code(uri),
         {:ok, fight_id} <- fight_id(uri) do
      {:ok,
       %{
         report_url: url,
         report_code: report_code,
         fight_id: fight_id
       }}
    end
  end

  def parse_report_url(_url), do: {:error, :invalid_url}

  @doc """
  Associates a WCL report URL with an imported combat-log file.
  """
  def associate_report(%CombatLogFile{} = combat_log_file, url) do
    with {:ok, parsed} <- parse_report_url(url) do
      combat_log_file
      |> change(%{
        warcraft_logs_report_url: parsed.report_url,
        warcraft_logs_report_code: parsed.report_code,
        warcraft_logs_fight_id: parsed.fight_id,
        warcraft_logs_linked_at: DateTime.utc_now()
      })
      |> Repo.update()
    end
  end

  def clear_report_association(%CombatLogFile{} = combat_log_file) do
    combat_log_file
    |> change(%{
      warcraft_logs_report_url: nil,
      warcraft_logs_report_code: nil,
      warcraft_logs_fight_id: nil,
      warcraft_logs_linked_at: nil
    })
    |> Repo.update()
  end

  defp report_code(%URI{path: path}) when is_binary(path) do
    case Regex.run(@report_path, path) do
      [_match, code] when code != "" -> {:ok, code}
      _ -> {:error, :missing_report_code}
    end
  end

  defp report_code(_uri), do: {:error, :missing_report_code}

  defp fight_id(%URI{} = uri) do
    [uri.query, uri.fragment]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("&")
    |> URI.decode_query()
    |> Map.get("fight")
    |> case do
      nil -> {:ok, nil}
      "" -> {:ok, nil}
      "last" -> {:ok, nil}
      value -> parse_positive_integer(value)
    end
  rescue
    ArgumentError -> {:error, :invalid_url}
  end

  defp parse_positive_integer(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _ -> {:error, :invalid_fight_id}
    end
  end
end
