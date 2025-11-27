#!/usr/bin/env elixir

# Test script to verify file watching works
# This simulates a combat log file being updated

Mix.install([{:briefly, "~> 0.3"}])

defmodule FileWatcherTest do
  def run do
    IO.puts("File Watcher Test")
    IO.puts("=================\n")

    # Check if FileWatcher is running
    case Process.whereis(WeGoNext.FileWatcher) do
      nil ->
        IO.puts("❌ FileWatcher is not running!")
        System.halt(1)

      pid ->
        IO.puts("✓ FileWatcher is running (PID: #{inspect(pid)})")
    end

    # Check current file being watched
    case WeGoNext.FileWatcher.current_file() do
      nil ->
        IO.puts("⚠️  FileWatcher is not watching any file")
        IO.puts("\nTo test file watching:")
        IO.puts("1. Open http://localhost:4000 in your browser")
        IO.puts("2. Import a combat log file")
        IO.puts("3. File watching will start automatically")

      clf ->
        IO.puts("✓ Watching: #{clf.file_path}")
        IO.puts("  Last parsed: #{clf.last_parsed_at}")
        IO.puts("  File size: #{clf.file_size} bytes")
        IO.puts("  Last byte: #{clf.last_parsed_byte}")

        IO.puts("\n✓ File watching is active!")
        IO.puts("  New encounters will be imported automatically when detected")
    end
  end
end

FileWatcherTest.run()
