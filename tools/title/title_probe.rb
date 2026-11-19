# SPDX-License-Identifier: GPL-3.0-or-later
# rmxp3ds title probe: an mkxp-z preloadScript (runs before the game's own scripts) that reports
# when a game reaches its title screen, without changing the game. A TracePoint notices when the
# game's scripts define a known title scene class; the probe then hooks the method that opens the
# title and the title's per-frame update, and after HOLD frames on the title writes
#   sdmc:/rmxp3ds/test/realtitle.txt   RMXP3DS_TEST realtitle PASS title_after=... title_fps=...
# Every step is appended to sdmc:/rmxp3ds/test/realtitle-log.txt at once (file closed each time),
# so a crash or freeze keeps the log. Known title scenes: Pokémon Essentials v21
# (IntroEventScene#open_title_screen, #title_screen_update) and the RPG Maker XP default scripts
# (Scene_Title#main, #update). Graphics.update is not wrapped: games alias it in its singleton
# class, and an alias of a prepended wrapper recurses.
module RMXP3DSTitleProbe
  LOG = 'sdmc:/rmxp3ds/test/realtitle-log.txt'
  RESULT = 'sdmc:/rmxp3ds/test/realtitle.txt'
  HOLD = 240 # frames on the title screen before reporting

  @t0 = System.uptime
  @frames = 0
  @hooked = {}
  @title_at = nil
  @title_frames = 0
  @done = false

  class << self
    # Appends one line with the time since start to the log (and stderr).
    def log(text)
      line = format('%7.2f s  %s', System.uptime - @t0, text)
      File.open(LOG, 'a') { |f| f.puts(line) }
      $stderr.puts("realtitle: #{line}")
    end

    # Called once per frame on the title screen.
    def tick
      @frames += 1
      return unless @title_at && !@done

      @title_frames += 1
      return unless @title_frames == HOLD

      @done = true
      fps = HOLD / (System.uptime - @title_at)
      line = format('RMXP3DS_TEST realtitle PASS title_after=%.1fs title_fps=%.1f frames=%d',
                    @title_at - @t0, fps, @frames)
      log(line)
      File.write(RESULT, line + "\n")
    end

    # Prepends mod to klass (once), called when the game closes the class's definition.
    def hook(klass, mod)
      return if @hooked[klass]

      klass.prepend(mod)
      @hooked[klass] = true
      log("#{klass.name} hooked")
    end

    def class_defined(klass)
      case klass.name
      when 'IntroEventScene' then hook(klass, EssentialsHook)
      when 'Scene_Title' then hook(klass, RmxpHook)
      end
    end

    def title_opened(what)
      return if @title_at

      @title_at = System.uptime
      log("title screen opened (#{what})")
    end
  end

  # Pokémon Essentials v21: splash images, then the title screen.
  module EssentialsHook
    def open_splash(*args)
      RMXP3DSTitleProbe.log('splash')
      super
    end

    def open_title_screen(*args)
      result = super
      RMXP3DSTitleProbe.title_opened('IntroEventScene#open_title_screen')
      result
    end

    def title_screen_update(*args)
      result = super
      RMXP3DSTitleProbe.tick
      result
    end
  end

  # RPG Maker XP default scripts: Scene_Title#main draws the title and loops until a choice.
  module RmxpHook
    def main(*args)
      RMXP3DSTitleProbe.title_opened('Scene_Title#main')
      super
    end

    def update(*args)
      result = super
      RMXP3DSTitleProbe.tick
      result
    end
  end

  TRACE = TracePoint.new(:end) { |tp| class_defined(tp.self) if tp.self.is_a?(Class) }
end

Dir.mkdir('sdmc:/rmxp3ds/test') unless Dir.exist?('sdmc:/rmxp3ds/test')
File.write(RMXP3DSTitleProbe::LOG, "realtitle probe loaded\n")
RMXP3DSTitleProbe::TRACE.enable
