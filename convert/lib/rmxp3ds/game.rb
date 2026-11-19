# SPDX-License-Identifier: GPL-3.0-or-later
# A game directory as the converter sees it: Game.ini, the script sections (Data/Scripts.rxdata
# and Essentials' Data/PluginScripts.rxdata), the profile (which patch set and screen size) and
# an index of its files.
require 'zlib'
require_relative 'marshal_loader'

module RMXP3DS
  class ConvertError < StandardError; end

  # Known game families. The first whose `match` hits the script text wins; otherwise the
  # plain RPG Maker XP profile. `patch_set` names patches/<patch_set>/ in this repository.
  PROFILES = [
    {
      id: 'essentials-v21', name: 'Pokémon Essentials v21',
      match: ->(text) { text.match?(/module Essentials\b.*?\bVERSION\s*=\s*"21\./m) },
      patch_set: 'essentials-v21'
    }
  ].freeze
  RMXP_PROFILE = { id: 'rmxp', name: 'RPG Maker XP', patch_set: nil }.freeze

  class Game
    # Script section: name and source (binary string).
    Section = Struct.new(:origin, :name, :text)

    attr_reader :dir, :ini, :sections, :profile

    def initialize(dir)
      @dir = File.expand_path(dir)
      raise ConvertError, "#{dir}: not a directory" unless File.directory?(@dir)
      @ini = read_ini
      @sections = read_sections
      text = script_text
      @profile = PROFILES.find { |p| p[:match].call(text) } || RMXP_PROFILE
    end

    def title
      @ini.dig('Game', 'Title') || File.basename(@dir)
    end

    # All script sources joined (for detection and scans).
    def script_text
      @script_text ||= @sections.map(&:text).join("\n")
    end

    # Width and height of the game screen: Essentials' Settings::SCREEN_WIDTH/HEIGHT, else the
    # first literal Graphics.resize_screen(w, h), else RGSS1's 640x480.
    def screen_size
      text = script_text
      w = text[/^\s*SCREEN_WIDTH\s*=\s*(\d+)/, 1]
      h = text[/^\s*SCREEN_HEIGHT\s*=\s*(\d+)/, 1]
      return [w.to_i, h.to_i] if w && h
      m = text.match(/Graphics\.resize_screen\(\s*(\d+)\s*,\s*(\d+)\s*\)/)
      m ? [m[1].to_i, m[2].to_i] : [640, 480]
    end

    # Relative paths of all files (forward slashes), sorted.
    def files
      @files ||= Dir.glob('**/*', File::FNM_DOTMATCH, base: @dir)
                    .reject { |f| File.basename(f) == '.' || File.basename(f) == '..' }
                    .select { |f| File.file?(File.join(@dir, f)) }.sort
    end

    # Index for case-insensitive lookups without extension: "graphics/tilesets/outside" =>
    # ["Graphics/Tilesets/Outside.png"].
    def file_index
      @file_index ||= files.group_by { |f| f.sub(/\.[^.\/]*\z/, '').downcase }
    end

    # Path to a data file (case-insensitive), or nil.
    def data_path(name)
      rel = files.find { |f| f.casecmp?("Data/#{name}") }
      rel && File.join(@dir, rel)
    end

    private

    # Game.ini as {section => {key => value}}; bytes kept as they are (titles may be CP1252).
    def read_ini
      rel = files.find { |f| f.casecmp?('Game.ini') }
      raise ConvertError, "#{@dir}: no Game.ini (not an RPG Maker XP game?)" unless rel
      ini = {}
      section = nil
      File.binread(File.join(@dir, rel)).sub(/\A\xEF\xBB\xBF/n, '').each_line do |line|
        line = line.chomp.strip
        if (m = line.match(/\A\[(.+)\]\z/))
          section = ini[m[1]] ||= {}
        elsif section && (m = line.match(/\A([^=;]+?)\s*=\s*(.*)\z/))
          section[m[1]] = m[2]
        end
      end
      ini
    end

    def read_sections
      scripts_rel = (@ini.dig('Game', 'Scripts') || 'Data\Scripts.rxdata').tr('\\', '/')
      path = files.find { |f| f.casecmp?(scripts_rel) }
      raise ConvertError, "#{@dir}: #{scripts_rel} missing (encrypted Game.rgssad games are not supported)" unless path
      list = Data.load_file(File.join(@dir, path))
      unless list.is_a?(Array) && list.all? { |s| s.is_a?(Array) && s.size >= 3 }
        raise ConvertError, "#{path}: not an RPG Maker XP script list"
      end
      sections = list.map { |_id, name, code| Section.new(path, name.to_s, inflate(code)) }
      plugins = data_path('PluginScripts.rxdata')
      sections.concat(plugin_sections(plugins)) if plugins
      sections
    rescue Zlib::Error, ArgumentError, TypeError => e
      raise ConvertError, "#{path}: cannot read the scripts (#{e.message})"
    end

    def inflate(code)
      Zlib::Inflate.inflate(code.to_s).b
    end

    # Essentials' compiled plugins: nested arrays with deflated sources somewhere inside; every
    # string that inflates is taken as a section.
    def plugin_sections(path)
      found = []
      walk = lambda do |obj, name|
        case obj
        when Array
          label = obj.find { |o| o.is_a?(String) && o.end_with?('.rb') } || name
          obj.each { |o| walk.call(o, label) }
        when Hash then obj.each_value { |o| walk.call(o, name) }
        when String
          text = begin
            Zlib::Inflate.inflate(obj)
          rescue Zlib::Error
            nil
          end
          found << Section.new('Data/PluginScripts.rxdata', name.to_s, text.b) if text
        end
      end
      walk.call(Data.load_file(path), 'plugin')
      found
    end
  end
end
