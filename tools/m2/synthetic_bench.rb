# SPDX-License-Identifier: GPL-3.0-or-later
# Benchmark/test for the synthetic game (tools/m2/synthetic, CI): runs FRAMES frames of
# SynthMap#update with the headless clock and checks the result. Raises on failure, so the
# 3DS test app reports FAIL. Evaluated by load_game.rb after the game's scripts.
# ENV: FRAMES (default 600), EXPECT_DIGEST (if set: the digest must match, e.g. the host's).
frames = (ENV['FRAMES'] || 600).to_i
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

state = 12_345
rnd = -> { state = (state * 1_103_515_245 + 12_345) & 0x7fffffff }
map = SynthMap.new(1)
raise 'no events loaded' if map.events.empty?

uptime0 = System.uptime
times = Array.new(frames) do
  a = clock.call
  map.update(rnd)
  Graphics.update
  clock.call - a
end
elapsed_game = System.uptime - uptime0
expected_game = frames.to_f / Graphics.frame_rate
raise "game clock: #{elapsed_game} s, expected #{expected_game} s" if (elapsed_game - expected_game).abs > 1e-6

steps = map.events.sum(&:steps)
raise 'no event moved' if steps.zero?
raise 'event left the map' unless map.events.all? { |e| e.x.between?(0, map.width - 1) && e.y.between?(0, map.height - 1) }

digest = map.digest
expect = ENV['EXPECT_DIGEST'].to_s
raise "digest #{digest} != expected #{expect}" if !expect.empty? && digest != expect.to_i

t = times.sort
line = format('synthetic frames=%d events=%d steps=%d digest=%d avg=%.3f ms p95=%.3f ms',
              frames, map.events.size, steps, digest, t.sum / t.size * 1000,
              t[(t.size * 0.95).to_i] * 1000)
$stderr.puts line
$m2_result = "#{$m2_load}\n#{line}\n"
