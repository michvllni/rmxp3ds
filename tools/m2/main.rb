# SPDX-License-Identifier: GPL-3.0-or-later
# 3DS entry point (copied to sdmc:/rmxp3ds/test/main.rb; run by tools/bench): loads a game from
# SD into the headless RGSS environment and runs a benchmark from sdmc:/rmxp3ds/m2.
# Settings: optional KEY=VALUE lines in sdmc:/rmxp3ds/m2/env.txt, copied into ENV:
#   M2_GAME   game directory (default sdmc:/rmxp3ds/games/essentials)
#   M2_BENCH  benchmark file in sdmc:/rmxp3ds/m2 (default essentials_bench.rb)
#   and the benchmark's own settings (see its header).
# Returns the result text, which tools/bench writes to rubybench-results.txt.
m2 = 'sdmc:/rmxp3ds/m2'
$stderr.sync = true
if File.exist?("#{m2}/env.txt")
  File.readlines("#{m2}/env.txt", chomp: true).each do |line|
    key, value = line.split('=', 2)
    ENV[key] = value.to_s if key && !key.empty?
  end
end
ARGV.replace([ENV['M2_GAME'] || 'sdmc:/rmxp3ds/games/essentials', "#{m2}/rpg1.rb",
              "#{m2}/#{ENV['M2_BENCH'] || 'essentials_bench.rb'}"])
load "#{m2}/load_game.rb"
$m2_result
