defmodule Mix.Tasks.Wgn.ImportWarcraftLogs do
  @moduledoc """
  Imports saved Warcraft Logs API response JSON into source-data tables.

  The import records external parser evidence only. It does not import local
  combat logs, sync active mechanics, or rebuild failures.

  Usage:

      mix wgn.import_warcraft_logs --file /path/to/response.json --report-code abc123 --fight-id 17 --query-name Events
      mix wgn.import_warcraft_logs --report-code abc123 --fight-id 17 --preset damage-done --access-token "$WARCRAFT_LOGS_ACCESS_TOKEN"
      mix wgn.import_warcraft_logs --file response.json --report-code abc123 --fight-id 17 --query-name Events --query-file query.graphql --request-params-file request.json
  """

  use Mix.Task

  alias WeGoNext.SourceData

  @shortdoc "Import saved Warcraft Logs API response evidence"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args!(args)
    attrs = attrs_from_opts!(opts)

    result =
      case Keyword.get(opts, :file) do
        nil ->
          fetch_and_import!(attrs, opts)

        file ->
          SourceData.import_warcraft_logs_api_response_file(file, attrs)
      end

    case result do
      {:ok, result} ->
        Mix.shell().info(format_result(result, opts))

      {:error, reason} ->
        Mix.raise("Failed to import Warcraft Logs API source data: #{inspect(reason)}")
    end
  end

  defp parse_args!(args) do
    case OptionParser.parse(args,
           strict: [
             file: :string,
             report_code: :string,
             fight_id: :integer,
             source_url: :string,
             query_name: :string,
             query_document: :string,
             query_file: :string,
             query_variables_file: :string,
             request_params_file: :string,
             metadata_file: :string,
             preset: :string,
             access_token: :string,
             bronze_root: :string,
             compare_encounter_dim_id: :integer,
             api_endpoint: :string,
             api_version: :string,
             fetched_at: :string,
             product: :string,
             channel: :string,
             build_version: :string,
             build_key: :string,
             locale: :string,
             source_system: :string
           ]
         ) do
      {opts, [], []} ->
        opts

      {_opts, extra, []} ->
        Mix.raise("Unexpected argument(s): #{Enum.join(extra, " ")}")

      {_opts, _extra, invalid} ->
        invalid_args =
          invalid
          |> Enum.map(fn {arg, _value} -> arg end)
          |> Enum.join(", ")

        Mix.raise("Invalid option(s): #{invalid_args}")
    end
  end

  defp attrs_from_opts!(opts) do
    required_opt!(opts, :report_code, "--report-code")
    required_opt!(opts, :fight_id, "--fight-id")

    opts
    |> Keyword.take([
      :report_code,
      :fight_id,
      :source_url,
      :query_name,
      :api_endpoint,
      :api_version,
      :fetched_at,
      :product,
      :channel,
      :build_version,
      :build_key,
      :locale,
      :source_system,
      :bronze_root
    ])
    |> maybe_put_query_name(opts)
    |> maybe_put_query_document(opts)
    |> maybe_put_preset_query(opts)
    |> maybe_put_json_file(:query_variables, opts, :query_variables_file)
    |> maybe_put_json_file(:request_params, opts, :request_params_file)
    |> maybe_put_json_file(:metadata, opts, :metadata_file)
  end

  defp maybe_put_query_name(attrs, opts) do
    cond do
      Keyword.has_key?(opts, :query_name) ->
        attrs

      Keyword.get(opts, :preset) == "damage-done" ->
        Keyword.put(attrs, :query_name, "DamageDoneTable")

      true ->
        required_opt!(opts, :query_name, "--query-name")
        attrs
    end
  end

  defp maybe_put_query_document(attrs, opts) do
    cond do
      Keyword.has_key?(opts, :query_document) ->
        Keyword.put(attrs, :query_document, Keyword.fetch!(opts, :query_document))

      Keyword.has_key?(opts, :query_file) ->
        Keyword.put(attrs, :query_document, read_file!(Keyword.fetch!(opts, :query_file)))

      true ->
        attrs
    end
  end

  defp maybe_put_preset_query(attrs, opts) do
    case Keyword.get(opts, :preset) do
      nil ->
        attrs

      "damage-done" ->
        attrs
        |> Keyword.put_new(:query_name, "DamageDoneTable")
        |> Keyword.put_new(:query_document, damage_done_query())
        |> Keyword.put_new(:query_variables, %{
          "code" => Keyword.fetch!(opts, :report_code),
          "fightIDs" => [Keyword.fetch!(opts, :fight_id)]
        })

      preset ->
        Mix.raise("Unsupported Warcraft Logs preset: #{preset}")
    end
  end

  defp maybe_put_json_file(attrs, key, opts, opt_key) do
    if Keyword.has_key?(opts, opt_key) do
      Keyword.put(attrs, key, read_json_file!(Keyword.fetch!(opts, opt_key)))
    else
      attrs
    end
  end

  defp required_opt!(opts, key, flag) do
    case Keyword.get(opts, key) do
      nil -> Mix.raise("Warcraft Logs API import requires #{flag}")
      value -> value
    end
  end

  defp read_file!(path) do
    case File.read(path) do
      {:ok, body} -> body
      {:error, reason} -> Mix.raise("Could not read #{path}: #{inspect(reason)}")
    end
  end

  defp read_json_file!(path) do
    with {:ok, body} <- File.read(path),
         {:ok, payload} <- Jason.decode(body) do
      payload
    else
      {:error, reason} -> Mix.raise("Could not read JSON #{path}: #{inspect(reason)}")
    end
  end

  defp fetch_and_import!(attrs, opts) do
    access_token =
      Keyword.get(opts, :access_token) || System.get_env("WARCRAFT_LOGS_ACCESS_TOKEN") ||
        Mix.raise("Warcraft Logs API fetch requires --access-token or WARCRAFT_LOGS_ACCESS_TOKEN")

    query_document =
      Keyword.get(attrs, :query_document) ||
        Mix.raise("Warcraft Logs API fetch requires --query-file, --query-document, or --preset")

    query_variables = Keyword.get(attrs, :query_variables, %{})
    api_endpoint = Keyword.get(attrs, :api_endpoint, "https://www.warcraftlogs.com/api/v2/client")

    case post_graphql(api_endpoint, access_token, query_document, query_variables) do
      {:ok, response_payload} ->
        attrs
        |> Keyword.put(:response_payload, response_payload)
        |> SourceData.import_warcraft_logs_api_response()

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp post_graphql(api_endpoint, access_token, query_document, query_variables) do
    body = Jason.encode!(%{query: query_document, variables: query_variables})

    :inets.start()
    :ssl.start()

    request = {
      String.to_charlist(api_endpoint),
      [
        {~c"authorization", String.to_charlist("Bearer #{access_token}")},
        {~c"content-type", ~c"application/json"},
        {~c"accept", ~c"application/json"}
      ],
      ~c"application/json",
      body
    }

    case :httpc.request(:post, request, [], body_format: :binary) do
      {:ok, {{_version, status, _reason}, _headers, response_body}} when status in 200..299 ->
        Jason.decode(response_body)

      {:ok, {{_version, status, reason}, _headers, response_body}} ->
        {:error, {:http_error, status, to_string(reason), response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_result(result, opts) do
    fetch = result.fetch

    message =
      "Imported Warcraft Logs API source data for report #{fetch.report_code} " <>
        "fight #{fetch.fight_id}: " <>
        "#{source_import_label(result.source_import_action)}, " <>
        "response #{String.slice(fetch.response_hash, 0, 12)}, " <>
        "bronze artifact #{fetch.artifact_path}."

    case Keyword.get(opts, :compare_encounter_dim_id) do
      nil ->
        message

      encounter_dim_id ->
        message <> "\n" <> format_damage_done_comparison(encounter_dim_id, fetch)
    end
  end

  defp format_damage_done_comparison(encounter_dim_id, fetch) do
    case SourceData.compare_warcraft_logs_damage_done(encounter_dim_id, fetch) do
      {:ok, comparison} ->
        "Damage done comparison: local #{format_integer(comparison.local_total)} vs WCL " <>
          "#{format_integer(comparison.warcraft_logs_total)} " <>
          "(delta #{format_integer(comparison.delta)}, #{format_percent(comparison.delta_percent)}). " <>
          "#{comparison.matched_count} matched, #{comparison.mismatched_count} mismatched, " <>
          "#{comparison.local_only_count} local-only, " <>
          "#{comparison.warcraft_logs_only_count} WCL-only."

      {:error, reason} ->
        "Damage done comparison failed: #{inspect(reason)}."
    end
  end

  defp source_import_label(:inserted), do: "1 new source import"
  defp source_import_label(:updated), do: "1 refreshed source import"

  defp damage_done_query do
    """
    query DamageDoneTable($code: String!, $fightIDs: [Int]) {
      reportData {
        report(code: $code) {
          table(dataType: DamageDone, fightIDs: $fightIDs)
        }
      }
    }
    """
  end

  defp format_integer(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_percent(nil), do: "n/a"
  defp format_percent(value), do: :erlang.float_to_binary(value, decimals: 2) <> "%"
end
