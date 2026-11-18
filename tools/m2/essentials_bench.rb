# SPDX-License-Identifier: GPL-3.0-or-later
# M2 go/no-go benchmark for a Pokemon Essentials v21.1 game (docs/PLAN.md M2). Evaluated by
# load_game.rb after the game's scripts; uses Essentials' own classes. Game files stay local
# (never in the repository). Result lines go to stderr and $m2_result.
#   A: overworld logic per frame on the maps in MAPS (debug walk in a square, all events update)
#   B: the same plus Essentials' Ruby sprite updates (spritesets incl. its Ruby tilemap renderer)
#   C: AI-vs-AI trainer battles (3 vs 3, level 50, random species) without visuals
# ENV: OVERWORLD_FRAMES (default 600), MAPS (default "41,31": Route 5 and Route 3 of the v21.1
# demo; empty: skip A/B), BATTLES (default 5). SIM_FPS (rgss_headless.rb) sets the game clock.

def pbChooseLanguage = 0 # headless: no language menu

clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
out = []
report = ->(s) { out << s; $stderr.puts(s) }
stats = lambda do |name, times|
  t = times.sort
  avg = t.sum / t.size
  report.call(format('%-28s frames=%d avg=%.2f ms p50=%.2f p95=%.2f max=%.2f', name, t.size,
                     avg * 1000, t[t.size / 2] * 1000, t[(t.size * 0.95).to_i] * 1000, t[-1] * 1000))
end

t0 = clock.call
Game.initialize
Game.set_up_system
Game.start_new
report.call(format('setup new game: %.0f ms (map %d, %d events)', (clock.call - t0) * 1000,
                   $game_map.map_id, $game_map.events.size))

# Walk a 4-tile square: down, right, up, left, 16 frames each. $DEBUG + CTRL: Essentials' debug
# walk (through walls, no trainer sight, no wild encounters), so nothing opens a battle scene;
# all events keep updating.
$DEBUG = true
Input.held = [Input::CTRL]
Input.script = ->(f) { [2, 6, 8, 4][(f / 16) % 4] }
frames = (ENV['OVERWORLD_FRAMES'] || 600).to_i
raise 'OVERWORLD_FRAMES must be at least 1' if frames < 1
maps = (ENV['MAPS'] || '41,31').split(',').map(&:to_i)

logic = lambda do
  pbMapInterpreter.update
  $game_player.update
  $scene.updateMaps
  $game_system.update
  $game_screen.update
  Graphics.update
end

maps.each do |map_id|
  $map_factory.setup(map_id)
  $game_player.moveto($game_map.width / 2, $game_map.height / 2)
  $game_player.refresh
  pbMapInterpreter.clear
  $scene.instance_variable_set(:@spritesets, {}) # logic-only phase: no sprites yet
  # A: game logic only (Scene_Map#update before updateSpritesets)
  60.times { logic.call }
  GC.start
  gc0 = GC.count
  times = Array.new(frames) { a = clock.call; logic.call; clock.call - a }
  stats.call("map#{map_id}_logic(#{$game_map.events.size} ev)", times)
  report.call("  gc_runs=#{GC.count - gc0} player=#{$game_player.x},#{$game_player.y}")
  # B: plus Essentials' Ruby sprite updates (incl. its Ruby TilemapRenderer: upper bound)
  $scene.createSpritesets
  60.times { $scene.update; Graphics.update }
  GC.start
  times = Array.new(frames) { a = clock.call; $scene.update; Graphics.update; clock.call - a }
  stats.call("map#{map_id}_with_spritesets", times)
  $stderr.puts "map#{map_id}: disposing spritesets"
  $scene.disposeSpritesets
  $stderr.puts "map#{map_id}: done"
end

# C: complete AI-vs-AI battles (damage calc, AI, effects) without visuals
calc_count = 0
calc_time = 0.0
Battle::Move.class_eval do
  alias_method :m2_orig_pbCalcDamage, :pbCalcDamage
  define_method(:pbCalcDamage) do |*args|
    a = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    r = m2_orig_pbCalcDamage(*args)
    calc_time += Process.clock_gettime(Process::CLOCK_MONOTONIC) - a
    calc_count += 1
    r
  end
end
$stderr.puts 'battles: species'
# The visual-less debug scene's pbUpdate is empty, but the battle waits on System.uptime (ability
# splash): like the real scene's pbUpdate (pbGraphicsUpdate), let it pass a frame.
Battle::DebugSceneNoVisuals.class_eval { define_method(:pbUpdate) { |*| Graphics.update } }
species = GameData::Species.keys.select { |k| GameData::Species.get(k).form == 0 }.first(151)
battles = (ENV['BATTLES'] || 5).to_i
turns = 0
battle_time = 0.0
battles.times do |n|
  srand(1000 + n)
  t1 = NPCTrainer.new('A', :YOUNGSTER)
  t2 = NPCTrainer.new('B', :YOUNGSTER)
  3.times { t1.party.push(Pokemon.new(species.sample, 50)) }
  3.times { t2.party.push(Pokemon.new(species.sample, 50)) }
  battle = Battle.new(Battle::DebugSceneNoVisuals.new, t1.party, t2.party, [t1], [t2])
  battle.debug = true
  battle.controlPlayer = true
  battle.internalBattle = false
  $stderr.puts "battle #{n}: start"
  a = clock.call
  battle.pbStartBattle
  battle_time += clock.call - a
  turns += battle.turnCount
  $stderr.puts format('battle %d: %d turns, %.0f ms', n, battle.turnCount, (clock.call - a) * 1000)
end
report.call(format('battles=%d turns=%d ms_per_turn=%.2f damage_calcs=%d ms_per_calc=%.3f',
                   battles, turns, battle_time * 1000 / [turns, 1].max, calc_count,
                   calc_time * 1000 / [calc_count, 1].max))
$m2_result = ([$m2_load] + out).join("\n") + "\n"
