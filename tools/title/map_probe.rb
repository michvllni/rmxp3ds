# SPDX-License-Identifier: GPL-3.0-or-later
# rmxp3ds map probe: an mkxp-z preloadScript (runs before the game's own scripts) for the M4
# baseline. It measures a Pokémon Essentials v21 game walking around its maps in the real
# runtime, without changing the game's files:
# - Essentials' intro scene (Scene_Intro, what pbCallTitle returns) is replaced when the game's
#   scripts define it (TracePoint on class definitions, as in title_probe.rb): a new game starts
#   (Game.start_new) and the player is moved to each map in MAPS, then Essentials' own Scene_Map
#   runs as usual. Not via Object.prepend: on the 3DS that crashed Ruby's compiler while the
#   game's scripts loaded (NOTES.md, M4 findings).
# - Input is scripted: the player walks a 4-tile square (down, right, up, left) with Essentials'
#   debug walk ($DEBUG plus CTRL held: through walls, no trainer sight, no wild encounters), so
#   no battle or message interrupts the walk. All events, sprites and the tilemap keep updating.
# - Per map: SETTLE frames, then FRAMES measured frames. Measured are the interval between
#   frames (Scene_Map#update to Scene_Map#update, includes Graphics.update) and the time spent in
#   Scene_Map#update (Ruby: game logic and Essentials' sprite and tilemap updates).
# Results: sdmc:/rmxp3ds/test/realmap.txt (first line RMXP3DS_TEST realmap PASS|FAIL ...), step
# log realmap-log.txt (appended line by line, survives a crash), a snapshot per map
# (realmap-<id>.png: game content, keep it out of the repo).
module RMXP3DSMapProbe
  LOG = 'sdmc:/rmxp3ds/test/realmap-log.txt'
  RESULT = 'sdmc:/rmxp3ds/test/realmap.txt'
  # Route 5 (96 events) and Route 3 (30 events) of the Essentials v21.1 demo, as in M2 (tools/m2)
  MAPS = [41, 31].freeze
  SETTLE = 60
  FRAMES = 600
  STEP = 16 # frames per direction of the square walk
  DIRS = [2, 6, 8, 4].freeze # down, right, up, left (Input.dir4 values)

  @t0 = System.uptime
  @frame = 0
  @measuring = false

  class << self
    attr_reader :frame

    # Appends one line with the time since start to the log (and stderr).
    def log(text)
      line = format('%7.2f s  %s', System.uptime - @t0, text)
      File.open(LOG, 'a') { |f| f.puts(line) }
      $stderr.puts("realmap: #{line}")
    end

    # Direction of the scripted walk for the current frame.
    def dir
      DIRS[(@frame / STEP) % 4]
    end

    # avg/p50/p95/max in ms of a list of seconds.
    def stats(times)
      t = times.sort
      format('avg %.2f ms, p50 %.2f, p95 %.2f, max %.2f', t.sum / t.size * 1000,
             t[t.size / 2] * 1000, t[(t.size * 0.95).to_i] * 1000, t[-1] * 1000)
    end

    # Puts the player in the middle of map_id, like tools/m2/essentials_bench.rb.
    def go_to(map_id)
      $map_factory.setup(map_id)
      $game_player.moveto($game_map.width / 2, $game_map.height / 2)
      $game_player.refresh
      pbMapInterpreter.clear
      log("map #{map_id}: #{$game_map.width}x#{$game_map.height}, #{$game_map.events.size} events")
    end

    # Called from Scene_Map#update (prepended): counts frames, measures, moves to the next map.
    def around_update(scene)
      now = System.uptime
      @frame += 1
      @plan ||= MAPS.dup
      @map_start ||= @frame
      n = @frame - @map_start
      if n == SETTLE
        @intervals = []
        @updates = []
        @gc0 = GC.count
      elsif n > SETTLE && n <= SETTLE + FRAMES
        @intervals << now - @last
      end
      @last = now
      a = System.uptime
      result = yield
      @updates << System.uptime - a if n > SETTLE && n <= SETTLE + FRAMES
      finish_map(scene) if n == SETTLE + FRAMES
      result
    end

    def finish_map(scene)
      map_id = $game_map.map_id
      fps = @intervals.size / @intervals.sum
      @lines ||= []
      @lines << format('map%d events=%d frames=%d fps=%.1f frame: %s | update: %s | gc_runs=%d',
                       map_id, $game_map.events.size, @intervals.size, fps, stats(@intervals),
                       stats(@updates), GC.count - @gc0)
      log(@lines.last)
      snapshot(map_id)
      @plan.shift
      if @plan.empty?
        report
      else
        scene.disposeSpritesets
        go_to(@plan.first)
        scene.createSpritesets
        @map_start = @frame
      end
    end

    def snapshot(map_id)
      snap = Graphics.snap_to_bitmap
      path = "sdmc:/rmxp3ds/test/realmap-#{map_id}.png"
      snap.to_file(path)
      log("snapshot #{snap.width}x#{snap.height} -> #{path}")
      snap.dispose
    rescue StandardError => e
      log("snapshot: #{e.class}: #{e.message}")
    end

    def report
      worst = @lines.map { |l| l[/fps=([\d.]+)/, 1].to_f }.min
      head = format('RMXP3DS_TEST realmap PASS maps=%d min_fps=%.1f frame_rate=%d',
                    @lines.size, worst, Graphics.frame_rate)
      log(head)
      File.write(RESULT, ([head] + @lines).join("\n") + "\n")
      @done = true
    end

    def done? = @done
  end

  # Replaces Essentials' intro (splashes and title): a new game on the first map of MAPS.
  module IntroHook
    def main(*_args)
      RMXP3DSMapProbe.log('Scene_Intro#main: new game instead of the title')
      Scene_Map.prepend(SceneHook)
      Input.singleton_class.prepend(InputHook)
      Game.start_new # sets $scene to a new Scene_Map
      $DEBUG = true # Essentials' debug walk with CTRL (see InputHook)
      RMXP3DSMapProbe.go_to(MAPS.first)
    end
  end

  TRACE = TracePoint.new(:end) do |tp|
    next unless tp.self.is_a?(Class) && tp.self.name == 'Scene_Intro'

    tp.self.prepend(IntroHook)
    RMXP3DSMapProbe.log('Scene_Intro hooked')
    TRACE.disable
  end

  module SceneHook
    def update(*args)
      return super if RMXP3DSMapProbe.done?

      RMXP3DSMapProbe.around_update(self) { super }
    end
  end

  # Scripted input: the square walk with CTRL held. Other keys stay as they are.
  module InputHook
    def dir4
      RMXP3DSMapProbe.done? ? super : RMXP3DSMapProbe.dir
    end

    def press?(key)
      return true if key == Input::CTRL && !RMXP3DSMapProbe.done?

      super
    end
  end
end

Dir.mkdir('sdmc:/rmxp3ds/test') unless Dir.exist?('sdmc:/rmxp3ds/test')
File.write(RMXP3DSMapProbe::LOG, "realmap probe loaded\n")
RMXP3DSMapProbe::TRACE.enable
