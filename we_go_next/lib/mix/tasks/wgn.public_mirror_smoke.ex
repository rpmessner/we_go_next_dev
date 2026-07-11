defmodule Mix.Tasks.Wgn.PublicMirrorSmoke do
  @moduledoc """
  Runs the public mirror document smoke.

  The smoke rebuilds two local encounter documents, uploads them through the
  `mirror_uploads` outbox, verifies the uploaded public `index.json` and
  encounter documents, and optionally probes a deployed public app.

  Usage:

      mix wgn.public_mirror_smoke \\
        --factful-encounter-id 124 \\
        --zero-failure-encounter-id 456 \\
        --slug raid-night

      mix wgn.public_mirror_smoke \\
        --factful-encounter-id 124 \\
        --zero-failure-encounter-id 456 \\
        --slug raid-night \\
        --public-base-url https://we-go-next.example.com
  """

  use Mix.Task

  alias WeGoNext.PublicMirrorSmoke

  @shortdoc "Smoke-tests public mirror document upload and rendering"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args!(args)

    case PublicMirrorSmoke.run(opts) do
      {:ok, result} ->
        print_result(result)

      {:error, reason} ->
        Mix.raise("Public mirror smoke failed: #{inspect(reason)}")
    end
  end

  defp parse_args!(args) do
    {opts, extra, invalid} =
      OptionParser.parse(args,
        strict: [
          factful_encounter_id: :integer,
          zero_failure_encounter_id: :integer,
          slug: :string,
          public_base_url: :string,
          limit: :integer,
          max_concurrency: :integer
        ]
      )

    cond do
      invalid != [] ->
        Mix.raise("Invalid option(s): #{invalid |> Enum.map(&elem(&1, 0)) |> Enum.join(", ")}")

      extra != [] ->
        Mix.raise("Unexpected argument(s): #{Enum.join(extra, " ")}")

      true ->
        opts
    end
  end

  defp print_result(result) do
    Mix.shell().info("Public mirror smoke passed for /r/#{result.slug}.")
    Mix.shell().info("")
    Mix.shell().info("Factful encounter:")
    print_encounter(result.factful)
    Mix.shell().info("")
    Mix.shell().info("Zero-failure encounter:")
    print_encounter(result.zero_failure)
    Mix.shell().info("")
    Mix.shell().info("Outbox drain: #{inspect(result.drain)}")

    if result.public_probe do
      Mix.shell().info("")
      Mix.shell().info("Public page probes:")

      result.public_probe
      |> Enum.each(fn {name, probe} ->
        Mix.shell().info("- #{name}: HTTP #{probe.status}, #{probe.bytes} bytes, #{probe.url}")
      end)
    end

    Mix.shell().info("")
    Mix.shell().info("Post this result block to WE-34 and copy it to WE-11 and WE-12.")
  end

  defp print_encounter(encounter) do
    Mix.shell().info("- id: #{encounter.encounter_id}")
    Mix.shell().info("- name: #{encounter.name}")
    Mix.shell().info("- source key: #{encounter.source_encounter_key}")
    Mix.shell().info("- document key: #{encounter.document_key}")
    Mix.shell().info("- players: #{encounter.players}")
    Mix.shell().info("- failures: #{encounter.failures}")
    Mix.shell().info("- upload state: #{encounter.upload_state}")
  end
end
