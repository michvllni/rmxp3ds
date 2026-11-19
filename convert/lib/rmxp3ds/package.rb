# SPDX-License-Identifier: GPL-3.0-or-later
# Writes the SD card package of a game: OUT/rmxp3ds/games/<id>/ with the game's files (without
# PC-only files), mkxp.json for the 3DS runtime, the profile's patch set and the report; and the
# runtime app in OUT/3ds/rmxp3ds/ if given.
require 'fileutils'
require 'json'
require_relative 'game'
require_relative 'validate'

module RMXP3DS
  class Package
    REPO = File.expand_path('../../..', __dir__)
    # Left out of the package: Windows programs and libraries, editor and shortcut files, the
    # game's own mkxp.json (replaced), MIDI soundfonts (no MIDI on the 3DS yet, M6), OS litter.
    EXCLUDE_EXT = %w[.exe .dll .url .lnk .rxproj .sf2].freeze
    EXCLUDE_NAMES = %w[mkxp.json thumbs.db desktop.ini .ds_store].freeze
    EXCLUDE_DIRS = %w[.git rmxp3ds].freeze # rmxp3ds/: our own files in the package
    # Image height up to which the RGSS Tilemap of the runtime still draws a tileset (NOTES.md M4).
    RGSS_TILESET_HEIGHT = 1300

    attr_reader :game, :id, :height, :report, :validator

    # opts: id, out, height, patch_set ('auto', 'none' or a directory), preloads (files),
    # runtime (.3dsx or nil), clean (remove the package directory first).
    def initialize(game, opts)
      @game = game
      @opts = opts
      @id = opts[:id] || slug(game.title)
      raise ConvertError, "--id #{@id.inspect}: use letters, digits, '-' and '_'" unless @id.match?(/\A[A-Za-z0-9_-]+\z/)
      @height = opts[:height] || game.screen_size[1]
      @report = []
    end

    def dest
      File.join(@opts[:out], 'rmxp3ds', 'games', @id)
    end

    # Validates; writes the package unless there are errors (or dry_run). Returns true on success.
    def run(dry_run: false)
      included, excluded = @game.files.partition { |f| include?(f) }
      @validator = Validator.new(@game, included).run
      patches = patch_files
      write_report(included, excluded, patches)
      return false if @validator.errors?
      return true if dry_run

      FileUtils.rm_rf(dest) if @opts[:clean]
      copied = copy_files(included)
      FileUtils.mkdir_p(File.join(dest, 'rmxp3ds'))
      preload_paths = install_preloads(patches)
      File.write(File.join(dest, 'mkxp.json'), mkxp_json(preload_paths))
      @report << "copied #{copied} of #{included.size} files (others unchanged since the last run)"
      install_runtime
      File.write(File.join(dest, 'rmxp3ds', 'convert-report.txt'), "#{@report.join("\n")}\n")
      true
    end

    private

    def slug(title)
      s = title.to_s.dup.force_encoding('UTF-8')
      s = title.to_s.b unless s.valid_encoding?
      s = s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
      s.empty? ? 'game' : s[0, 40]
    end

    def include?(rel)
      parts = rel.split('/')
      return false if EXCLUDE_DIRS.include?(parts.first.downcase)
      name = parts.last.downcase
      return false if parts.size == 1 && EXCLUDE_NAMES.include?(name)
      return false if %w[thumbs.db desktop.ini .ds_store].include?(name)
      !EXCLUDE_EXT.include?(File.extname(name))
    end

    # [[source path, name in the package]] for the profile's patch set and the extra preloads.
    def patch_files
      set = @opts[:patch_set] || 'auto'
      dir = case set
            when 'none' then nil
            when 'auto' then @game.profile[:patch_set] && File.join(REPO, 'patches', @game.profile[:patch_set])
            else set
            end
      patches = dir ? Dir.glob(File.join(dir, '*.rb')).sort : []
      raise ConvertError, "patch set #{dir}: no *.rb files" if dir && patches.empty? && set != 'auto'
      list = patches.map { |p| [p, "rmxp3ds/patches/#{File.basename(p)}"] }
      Array(@opts[:preloads]).each_with_index do |p, i|
        raise ConvertError, "--preload #{p}: not found" unless File.file?(p)
        list << [p, format('rmxp3ds/preload/%02d_%s', i, File.basename(p))]
      end
      list
    end

    def copy_files(files)
      copied = 0
      files.each do |rel|
        src = File.join(@game.dir, rel)
        dst = File.join(dest, rel)
        next if same_file?(src, dst)
        FileUtils.mkdir_p(File.dirname(dst))
        FileUtils.cp(src, dst, preserve: true)
        copied += 1
      end
      copied
    end

    def same_file?(src, dst)
      File.file?(dst) && File.size(dst) == File.size(src) && File.mtime(dst).to_i == File.mtime(src).to_i
    end

    def install_preloads(patches)
      FileUtils.rm_rf(File.join(dest, 'rmxp3ds', 'patches'))
      FileUtils.rm_rf(File.join(dest, 'rmxp3ds', 'preload'))
      patches.map do |src, rel|
        FileUtils.mkdir_p(File.dirname(File.join(dest, rel)))
        FileUtils.cp(src, File.join(dest, rel))
        rel
      end
    end

    def factor
      240.0 / @height
    end

    def mkxp_json(preloads)
      <<~JSON
        // mkxp-z-3ds config written by rmxp3ds-convert (replaces the game's own mkxp.json)
        {
          "rgssVersion": 1,
          // rmxp3ds D15: the game screen (height #{@height}) scaled to the 3DS height, bitmaps at full size
          "enableHires": true,
          "framebufferScalingFactor": #{format('%.6f', factor)},
          "textureScalingFactor": 1.0,
          // no path cache: the SD card (FAT) already matches names without case, and listing
          // thousands of files took minutes at start (rmxp3ds NOTES.md M3, console attempt 4)
          "pathCache": false,
          "preloadScript": #{JSON.generate(preloads)}
        }
      JSON
    end

    def install_runtime
      return unless @opts[:runtime]
      dir = File.join(@opts[:out], '3ds', 'rmxp3ds')
      FileUtils.mkdir_p(dir)
      FileUtils.cp(@opts[:runtime], File.join(dir, 'mkxp-z.3dsx'))
      @report << "runtime: #{@opts[:runtime]} -> 3ds/rmxp3ds/mkxp-z.3dsx"
    end

    def mib(bytes)
      format('%.1f MiB', bytes / 1048576.0)
    end

    def write_report(included, excluded, patches)
      v = @validator
      size = ->(list) { list.sum { |f| File.size(File.join(@game.dir, f)) } }
      w, h = @game.screen_size
      r = @report
      r << "rmxp3ds-convert report for #{@game.title.dup.force_encoding('UTF-8').scrub('?')}"
      r << "game: #{@game.dir}"
      r << "package: #{dest} (SD card: rmxp3ds/games/#{@id}/)"
      r << "profile: #{@game.profile[:id]} (#{@game.profile[:name]})"
      r << "screen: #{w}x#{h}, height used #{@height}, scaling factor #{format('%.4f', factor)} (D15)"
      r << "scripts: #{@game.sections.size} sections"
      r << "patches: #{patches.empty? ? 'none' : patches.map(&:last).join(', ')}"
      r << "files: #{included.size} (#{mib(size.call(included))}); left out #{excluded.size} (#{mib(size.call(excluded))})"
      excluded.first(20).each { |f| r << "  left out: #{f}" }
      r << "  ... #{excluded.size - 20} more" if excluded.size > 20
      large = v.large_images
      unless large.empty?
        r << "images over #{Validator::TEXTURE_LIMIT} px: #{large.size} (drawn from CPU memory, slower)"
        large.each { |f, iw, ih| r << "  #{f}: #{iw}x#{ih}" }
        if @game.profile[:patch_set].nil?
          large.select { |f, _iw, ih| f.start_with?('Graphics/Tilesets/') && ih > RGSS_TILESET_HEIGHT }.each do |f, _iw, ih|
            v.findings << Finding.new(:warning, "#{f}: tileset #{ih} px tall; the RGSS Tilemap of the runtime " \
                                                'draws up to about 1300 px (needs a patch set with the native renderer, D17)')
          end
        end
      end
      unless v.missing.empty?
        r << "missing files named by the data: #{v.missing.size} (graphics/audio not in the game; RTP files are not added)"
        v.missing.each { |f, where| r << "  #{f} (#{where})" }
      end
      %i[error warning].each do |level|
        list = v.findings.select { |f| f.level == level }
        next if list.empty?
        r << "#{level}s: #{list.size}"
        list.each { |f| r << "  #{f.text}" }
      end
      r << (v.errors? ? 'result: FAILED (errors above, nothing written)' : 'result: OK')
    end
  end
end
