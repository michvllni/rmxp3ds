# SPDX-License-Identifier: GPL-3.0-or-later
# Loads a game's Data/Scripts.rxdata into the headless RGSS environment (all sections except
# "Main", whose rgss_main loop would start the game) and then evaluates a benchmark script.
#   ruby load_game.rb GAME_DIR RPG1_RB [BENCH_RB]
# On the 3DS, tools/m2/main.rb sets ARGV and loads this file. Sets $m2_load (one result line);
# the benchmark sets $m2_result. Loading stops at the first failing section.
require 'zlib'
game, rpg1 = ARGV[0], File.expand_path(ARGV[1])
bench = ARGV[2] && File.expand_path(ARGV[2])
require_relative 'rgss_headless'
load rpg1
Dir.chdir(game)
sections = Marshal.load(File.binread('Data/Scripts.rxdata'))
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
sections.each_with_index do |(_, name, code), i|
  next if name == 'Main'

  src = Zlib::Inflate.inflate(code).force_encoding('UTF-8')
  begin
    eval(src, TOPLEVEL_BINDING, "Section#{i}:#{name}") # rubocop:disable Security/Eval
  rescue Exception => e # rubocop:disable Lint/RescueException
    raise "loading section #{i} #{name} failed: #{e.class}: #{e.message[0, 200]}"
  end
end
$m2_load = format('loaded %d sections in %.2f s', sections.size,
                  Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0)
$stderr.puts $m2_load
$m2_result = "#{$m2_load}\n"
if bench
  srand(1)
  eval(File.read(bench), TOPLEVEL_BINDING, bench) # rubocop:disable Security/Eval
end
