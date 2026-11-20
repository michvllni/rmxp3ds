# SPDX-License-Identifier: GPL-3.0-or-later
# rmxp3ds battle probe: an mkxp-z preloadScript (runs before the game's own scripts) for the M6
# exit. It plays one wild battle of a Pokémon Essentials v21 game in the real runtime, without
# changing the game's files:
# - Essentials' intro scene (Scene_Intro) is replaced when the game's scripts define it
#   (TracePoint on class definitions, as in map_probe.rb): a new game starts (Game.start_new) on
#   MAP, the party is one level PARTY_LEVEL Pokémon that knows only MOVE, and on the first map
#   frame Essentials' own WildBattle.start runs against FOE at FOE_LEVEL, with Essentials' battle
#   scene, animations, messages, music and sounds.
# - Input is scripted: USE is triggered every PULSE frames (Fight, the first move, then every
#   message), nothing else. The level gap ends the battle in one turn.
# - Measured: the battle's outcome (WildBattle.start: true when won; older versions: 1), its
#   length, the frame intervals during the battle (Graphics.update to Graphics.update) and GC
#   runs.
# Results: sdmc:/rmxp3ds/test/realbattle.txt (first line RMXP3DS_TEST realbattle PASS|FAIL ...),
# step log realbattle-log.txt (appended line by line, survives a crash), snapshot
# realbattle.png in the battle (game content, keep it out of the repo).
module RMXP3DSBattleProbe
  LOG = 'sdmc:/rmxp3ds/test/realbattle-log.txt'
  RESULT = 'sdmc:/rmxp3ds/test/realbattle.txt'
  MAP = 41 # Route 5 of the Essentials v21.1 demo (as the M4 map run)
  PARTY = :PIKACHU
  PARTY_LEVEL = 100
  MOVE = :THUNDERSHOCK
  FOE = :PIDGEY
  FOE_LEVEL = 2
  PULSE = 10
  SNAPSHOT_FRAME = 300 # battle frame of the snapshot (the command menu or a message)
  MAX_FRAMES = 20_000  # gives up (FAIL) if the battle has not ended by then

  @t0 = System.uptime
  @frame = 0
  @in_battle = false
  @intervals = []

  class << self
    attr_reader :frame

    def in_battle? = @in_battle

    # Appends one line with the time since start to the log (and stderr).
    def log(text)
      line = format('%7.2f s  %s', System.uptime - @t0, text)
      File.open(LOG, 'a') { |f| f.puts(line) }
      $stderr.puts("realbattle: #{line}")
    end

    # avg/p50/p95/max in ms of a list of seconds.
    def stats(times)
      t = times.sort
      format('avg %.2f ms, p50 %.2f, p95 %.2f, max %.2f', t.sum / t.size * 1000,
             t[t.size / 2] * 1000, t[(t.size * 0.95).to_i] * 1000, t[-1] * 1000)
    end

    # Graphics.update (aliased in IntroHook#main): counts frames, measures during the battle.
    def on_frame
      now = System.uptime
      @frame += 1
      if @in_battle
        @intervals << now - @last if @last
        @battle_frames += 1
        snapshot if @battle_frames == SNAPSHOT_FRAME
        if @battle_frames > MAX_FRAMES && !@gave_up
          @gave_up = true
          report(nil, 'battle did not end')
        end
      end
      @last = now
    end

    def trigger_use?
      @in_battle && (@frame % PULSE).zero?
    end

    def set_party
      pkmn = Pokemon.new(PARTY, PARTY_LEVEL)
      pkmn.forget_all_moves
      pkmn.learn_move(MOVE)
      $player.party = [pkmn]
      log("party: #{PARTY} level #{PARTY_LEVEL} with #{MOVE}")
    end

    # Runs the battle (from Scene_Map#update, as an event's battle command would).
    def battle
      @started = true
      @in_battle = true
      @battle_frames = 0
      @gc0 = GC.count
      a = System.uptime
      log("WildBattle.start(#{FOE}, #{FOE_LEVEL})")
      outcome = WildBattle.start(FOE, FOE_LEVEL)
      @in_battle = false
      log(format('battle over: outcome %s after %.1f s, %d frames', outcome.inspect, System.uptime - a, @battle_frames))
      report(outcome, nil, System.uptime - a)
    rescue Exception => e # rubocop:disable Lint/RescueException
      @in_battle = false
      log("battle: #{e.class}: #{e.message} @ #{e.backtrace&.first(3)&.join(' | ')}")
      report(nil, "#{e.class}: #{e.message}")
    end

    def started? = @started

    def snapshot
      snap = Graphics.snap_to_bitmap
      snap.to_file('sdmc:/rmxp3ds/test/realbattle.png')
      log("snapshot #{snap.width}x#{snap.height} at battle frame #{@battle_frames}")
      snap.dispose
    rescue StandardError => e
      log("snapshot: #{e.class}: #{e.message}")
    end

    def report(outcome, error, secs = nil)
      return if @reported

      @reported = true
      ok = (outcome == 1 || outcome == true) && error.nil? # v21.1 WildBattle.start: true when won
      fps = @intervals.empty? ? 0 : @intervals.size / @intervals.sum
      head = format('RMXP3DS_TEST realbattle %s outcome=%s frames=%d fps=%.1f',
                    ok ? 'PASS' : 'FAIL', outcome.inspect, @battle_frames.to_i, fps)
      head += " error=#{error}" if error
      lines = [head]
      lines << format('battle %.1f s, frame: %s, gc_runs=%d', secs || 0, stats(@intervals), GC.count - @gc0.to_i) unless @intervals.empty?
      lines.each { |l| log(l) }
      File.write(RESULT, lines.join("\n") + "\n")
    end
  end

  # Replaces Essentials' intro (splashes and title): a new game on MAP with the probe's party.
  module IntroHook
    def main(*_args)
      RMXP3DSBattleProbe.log('Scene_Intro#main: new game instead of the title')
      Scene_Map.prepend(SceneHook)
      Input.singleton_class.prepend(InputHook)
      # Frame counter: an alias now, after the game's scripts. A module prepended to Graphics
      # before them recursed without end: Essentials aliases Graphics.update itself (Transitions).
      class << Graphics
        alias_method :rmxp3ds_probe_update, :update
        def update(*args)
          RMXP3DSBattleProbe.on_frame
          rmxp3ds_probe_update(*args)
        end
      end
      Game.start_new # sets $scene to a new Scene_Map
      $map_factory.setup(MAP)
      $game_player.moveto($game_map.width / 2, $game_map.height / 2)
      $game_player.refresh
      pbMapInterpreter.clear
      RMXP3DSBattleProbe.set_party
    end
  end

  TRACE = TracePoint.new(:end) do |tp|
    next unless tp.self.is_a?(Class) && tp.self.name == 'Scene_Intro'

    tp.self.prepend(IntroHook)
    RMXP3DSBattleProbe.log('Scene_Intro hooked')
    TRACE.disable
  end

  module SceneHook
    def update(*args)
      RMXP3DSBattleProbe.battle unless RMXP3DSBattleProbe.started?
      super
    end
  end

  # Scripted input: USE every PULSE frames during the battle. Other keys stay as they are.
  module InputHook
    def trigger?(key)
      return true if key == Input::USE && RMXP3DSBattleProbe.trigger_use?

      super
    end
  end
end

Dir.mkdir('sdmc:/rmxp3ds/test') unless Dir.exist?('sdmc:/rmxp3ds/test')
File.write(RMXP3DSBattleProbe::LOG, "realbattle probe loaded\n")
RMXP3DSBattleProbe::TRACE.enable
