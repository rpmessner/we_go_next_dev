#!/usr/bin/env elixir

# Script to test combat log parsing
log_path = "/mnt/g/World of Warcraft/_retail_/Logs/WoWCombatLog-112225_112043.txt"
player_name = "Mittwoch"

IO.puts("Parsing combat log: #{log_path}")
IO.puts("Looking for player: #{player_name}\n")

encounters = CombatLogParser.parse(log_path)

CombatLogParser.print_summary(encounters, player_name)
