# SPDX-License-Identifier: GPL-3.0-or-later
# Checks a game before packaging: file names the 3DS SD card (FAT32) cannot hold, graphics and
# audio the database, maps and events name but the game lacks, images over the 3DS texture
# limit, and script calls that cannot work on the 3DS (Win32API / DLLs).
require_relative 'marshal_loader'
require_relative 'images'

module RMXP3DS
  # One line of the report: level :error (no package), :warning or :info.
  Finding = Struct.new(:level, :text)

  class Validator
    IMAGE_EXT = %w[.png .jpg .jpeg .bmp].freeze
    AUDIO_EXT = %w[.ogg .wav .mp3 .mid .midi .wma].freeze
    TEXTURE_LIMIT = 1024 # gl3ds GL_MAX_TEXTURE_SIZE; larger bitmaps are drawn from the CPU
    FAT_BAD = /[<>:"\\|?*\x00-\x1f]/.freeze

    attr_reader :findings, :missing, :large_images

    def initialize(game, files)
      @game = game
      @files = files # the files that go into the package
      @findings = []
      @missing = {} # "Graphics/Characters/x" => first place that names it
      @large_images = []
    end

    def run
      @game.problems.each { |level, text| add(level, text) }
      check_names
      check_references
      check_images
      check_scripts
      self
    end

    def errors?
      @findings.any? { |f| f.level == :error }
    end

    private

    def add(level, text)
      @findings << Finding.new(level, text)
    end

    def check_names
      @files.each do |f|
        f.split('/').each do |part|
          next unless part.match?(FAT_BAD) || part.end_with?('.', ' ')
          add(:error, "#{f}: the name is not allowed on the 3DS SD card (FAT32)")
          break
        end
        add(:error, "#{f}: path longer than 200 characters") if f.bytesize > 200
      end
      @files.group_by(&:downcase).each_value do |same|
        next if same.size < 2
        add(:error, "#{same.join(', ')}: names differ only in case (one file on the SD card, FAT32)")
      end
    end

    # --- references in the data -------------------------------------------------------------

    # Notes dir/name as missing unless a file with one of the extensions (or none) exists, case
    # ignored. `alt` is a second directory that also counts (Essentials' Audio/SE/Anim).
    def ref(dir, name, where, exts, alt: nil)
      return if name.nil? || !name.is_a?(String) || name.empty?
      name = name.dup.force_encoding('UTF-8').scrub('?').tr('\\', '/')
      found = [dir, alt].compact.any? do |d|
        hits = @game.file_index["#{d}/#{name}".downcase]
        hits&.any? { |f| exts.include?(File.extname(f).downcase) || File.extname(f).empty? }
      end
      @missing["#{dir}/#{name}"] ||= where unless found
    end

    def img(dir, name, where)
      ref("Graphics/#{dir}", name, where, IMAGE_EXT)
    end

    def audio(dir, file, where, alt: nil)
      ref("Audio/#{dir}", file && file[:name], where, AUDIO_EXT, alt: alt) if file.is_a?(Data::Plain)
    end

    def load(name)
      path = @game.data_path(name)
      return nil unless path
      Data.load_file(path)
    rescue StandardError => e
      add(:warning, "Data/#{name}: cannot be read (#{e.class}: #{e.message})")
      nil
    end

    def check_references
      each_entry(load('Tilesets.rxdata')) do |t, i|
        where = "Tilesets.rxdata ##{i}"
        img('Tilesets', t[:tileset_name], where)
        Array(t[:autotile_names]).each { |a| img('Autotiles', a.to_s.sub(/\A\[\d+\]/, ''), where) }
        img('Panoramas', t[:panorama_name], where)
        img('Fogs', t[:fog_name], where)
        img('Battlebacks', t[:battleback_name], where)
      end
      if (sys = load('System.rxdata'))
        img('Windowskins', sys[:windowskin_name], 'System.rxdata')
        img('Titles', sys[:title_name], 'System.rxdata')
        img('Gameovers', sys[:gameover_name], 'System.rxdata')
        img('Transitions', sys[:battle_transition], 'System.rxdata')
        %i[title_bgm battle_bgm].each { |k| audio('BGM', sys[k], 'System.rxdata') }
        %i[battle_end_me gameover_me].each { |k| audio('ME', sys[k], 'System.rxdata') }
        %i[cursor_se decision_se cancel_se buzzer_se equip_se shop_se save_se load_se battle_start_se
           escape_se actor_collapse_se enemy_collapse_se].each { |k| audio('SE', sys[k], 'System.rxdata') }
      end
      each_entry(load('Actors.rxdata')) do |a, i|
        img('Characters', a[:character_name], "Actors.rxdata ##{i}")
        img('Battlers', a[:battler_name], "Actors.rxdata ##{i}")
      end
      each_entry(load('Enemies.rxdata')) { |e, i| img('Battlers', e[:battler_name], "Enemies.rxdata ##{i}") }
      %w[Items Weapons Armors Skills].each do |db|
        each_entry(load("#{db}.rxdata")) do |e, i|
          img('Icons', e[:icon_name], "#{db}.rxdata ##{i}")
          audio('SE', e[:menu_se], "#{db}.rxdata ##{i}")
        end
      end
      # Essentials plays animation sounds from Audio/SE/Anim (its battle animation player).
      anim_alt = @game.profile[:id].start_with?('essentials') ? 'Audio/SE/Anim' : nil
      each_entry(load('Animations.rxdata')) do |a, i|
        img('Animations', a[:animation_name], "Animations.rxdata ##{i}")
        Array(a[:timings]).each do |t|
          audio('SE', t[:se], "Animations.rxdata ##{i}", alt: anim_alt) if t.is_a?(Data::Plain)
        end
      end
      each_entry(load('CommonEvents.rxdata')) { |c, i| commands(c[:list], "CommonEvents.rxdata ##{i}") }
      check_maps
    end

    def each_entry(list)
      return unless list.is_a?(Array)
      list.each_with_index { |e, i| yield e, i if e.is_a?(Data::Plain) }
    end

    def check_maps
      infos = load('MapInfos.rxdata')
      ids = infos.is_a?(Hash) ? infos.keys.grep(Integer).sort : []
      ids.each do |id|
        name = format('Map%03d.rxdata', id)
        unless @game.data_path(name)
          add(:warning, "Data/#{name}: listed in MapInfos.rxdata but missing")
          next
        end
        map = load(name)
        next unless map.is_a?(Data::Plain)
        audio('BGM', map[:bgm], name) if map[:autoplay_bgm]
        audio('BGS', map[:bgs], name) if map[:autoplay_bgs]
        (map[:events] || {}).each_value do |ev|
          next unless ev.is_a?(Data::Plain)
          Array(ev[:pages]).each do |page|
            where = "#{name} event #{ev[:id]}"
            graphic = page[:graphic]
            img('Characters', graphic[:character_name], where) if graphic.is_a?(Data::Plain)
            route(page[:move_route], where)
            commands(page[:list], where)
          end
        end
      end
    end

    # Event commands that name files (codes per the RPG Maker XP event command list).
    def commands(list, where)
      Array(list).each do |c|
        next unless c.is_a?(Data::Plain)
        p = Array(c[:parameters])
        case c[:code]
        when 131 then img('Windowskins', p[0], where)
        when 204
          img('Panoramas', p[1], where) if p[0] == 0
          img('Fogs', p[1], where) if p[0] == 1
          img('Battlebacks', p[1], where) if p[0] == 2
        when 209 then route(p[1], where)
        when 222 then img('Transitions', p[0], where)
        when 231 then img('Pictures', p[1], where)
        when 132, 241 then audio('BGM', p[0], where)
        when 245 then audio('BGS', p[0], where)
        when 133, 249 then audio('ME', p[0], where)
        when 250 then audio('SE', p[0], where)
        when 322
          img('Characters', p[1], where)
          img('Battlers', p[3], where)
        end
      end
    end

    def route(route, where)
      return unless route.is_a?(Data::Plain)
      Array(route[:list]).each do |m|
        next unless m.is_a?(Data::Plain)
        p = Array(m[:parameters])
        img('Characters', p[0], where) if m[:code] == 41
        audio('SE', p[0], where) if m[:code] == 44
      end
    end

    # --- images and scripts -----------------------------------------------------------------

    def check_images
      @files.each do |f|
        next unless f.downcase.start_with?('graphics/') && IMAGE_EXT.include?(File.extname(f).downcase)
        w, h = Images.size(File.join(@game.dir, f))
        if w.nil?
          add(:warning, "#{f}: unknown image format or damaged header")
        elsif w > TEXTURE_LIMIT || h > TEXTURE_LIMIT
          @large_images << [f, w, h]
        end
      end
    end

    def check_scripts
      dlls = Hash.new { |h, k| h[k] = [] }
      @game.sections.each do |s|
        s.text.scan(/Win32API\.new\(\s*['"]([^'"]+)['"]/) { |m| dlls[m[0].downcase] << s.name }
        dlls['(dynamic)'] << s.name if s.text.match?(/Win32API\.new\(\s*[^'"\s]/)
        if s.text.match?(/\b(?:Fiddle|DL::|require\s+['"]win32)/)
          add(:warning, "script #{s.name.inspect}: uses Fiddle/DL/win32 (Windows only)")
        end
      end
      dlls.each do |dll, names|
        add(:warning, "Win32API #{dll}: #{names.uniq.size} script(s) (#{names.uniq.first(3).join(', ')}) " \
                      'call it; Windows DLLs do not exist on the 3DS, the calls fail unless a patch replaces them')
      end
    end
  end
end
