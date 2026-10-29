defmodule WeGoNext.Analysis.ReferenceScriptsTest do
  use ExUnit.Case, async: false

  test "reference and benchmark CLIs reproduce fixture evidence without a live Claude call" do
    scripts = Path.expand("../../../../scripts", __DIR__)

    {output, status} =
      System.cmd(
        "python3",
        ["-B", "-m", "unittest", "discover", "-s", Path.join(scripts, "tests")],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end
end
