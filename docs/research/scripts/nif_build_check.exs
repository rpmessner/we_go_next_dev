# Verify Zigler's generated build mode and NIF registration flags.
# Run immediately after a forced compile, from we_go_next/ (staging is shared
# across Mix environments, so do not compile another environment in between):
#
#   mix compile --force --warnings-as-errors
#   mix run --no-start ../docs/research/scripts/nif_build_check.exs
#
# Repeat with MIX_ENV=test to check the test build too. No database is started.

staging = Zig.Builder.staging_directory(WeGoNext.CombatLogParser)
build = File.read!(Path.join(staging, "build.zig"))
registration = File.read!(Path.join(staging, "module.zig"))

unless build =~ "const optimize: std.builtin.OptimizeMode = .ReleaseSafe;" do
  raise "CombatLogParser must build in ReleaseSafe (#{Mix.env()})"
end

for {name, arity} <- [{"parse_events", 4}, {"scan_boundaries", 2}] do
  pattern =
    ~r/\.name = "#{name}", \.arity = #{arity}, \.fptr = #{name}, \.flags = e\.ERL_NIF_DIRTY_JOB_CPU_BOUND/

  unless Regex.match?(pattern, registration) do
    raise "#{name}/#{arity} must register as a dirty CPU NIF (#{Mix.env()})"
  end
end

IO.puts("#{Mix.env()}: ReleaseSafe and dirty CPU registration for both parse NIFs PASS")
