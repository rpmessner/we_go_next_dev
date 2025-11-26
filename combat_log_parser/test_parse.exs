#!/usr/bin/env elixir

# Script to test combat log parsing
log_path = "/mnt/g/World of Warcraft/_retail_/Logs/WoWCombatLog-112225_112043.txt"

IO.puts("Parsing combat log: #{log_path}\n")

encounters = CombatLogParser.parse(log_path)

IO.puts("Found #{length(encounters)} encounters\n")

# Print death summary
CombatLogParser.print_death_summary(encounters)

# Print damage taken summary
CombatLogParser.print_damage_taken_summary(encounters, top: 5, show_abilities: 3)

# Print interrupt summary
CombatLogParser.print_interrupt_summary(encounters)

# Print debuff summary
CombatLogParser.print_debuff_summary(encounters, top_spells: 10, top_players: 5)
