# SPDX-License-Identifier: GPL-3.0-or-later
# Writes the SD card package of a game: OUT/rmxp3ds/games/<id>/ with the game's files (without
# PC-only files), mkxp.json for the 3DS runtime, the profile's patch set and the report; and the
# runtime app in OUT/3ds/rmxp3ds/ if given.
require 'digest'
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
    EXCLUDE_DIRS = %w[.git __macosx rmxp3ds].freeze # rmxp3ds/: our own files in the package
    # Name of the file in the package's rmxp3ds/ that records which game directory it came from.
    SOURCE_FILE = 'source.txt'
    # Image height up to which the RGSS Tilemap of the runtime still draws a tileset (NOTES.md M4).
    RGSS_TILESET_HEIGHT = 1300

    attr_reader :game, :id, :height, :report, :validator

    # opts: id, out, height, patch_set ('auto', 'none' or a directory), preloads (files),
    # runtime (.3dsx or nil), clean (remove the package directory first).
    def initialize(game, opts)
      @game = game
      @opts = opts
      @id = opts[:id] || slug(game.title)
      raise ArgumentsError, "--id #{@id.inspect}: use letters, digits, '-' and '_'" unless @id.match?(/\A[A-Za-z0-9_-]+\z/)
      @height = opts[:height] || game.screen_size[1]
      @report = []
      check_paths
    end

    def dest
      File.join(@opts[:out], 'rmxp3ds', 'games', @id)
    end

    # Validates; writes the package unless there are errors (or dry_run). Returns true on success.
    def run(dry_run: false)
      @dry_run = dry_run
      included, excluded = @game.files.partition { |f| include?(f) }
      @validator = Validator.new(@game, included).run
      patches = patch_files
      write_report(included, excluded, patches)
      return false if @validator.errors?
      return true if dry_run

      FileUtils.rm_rf(dest) if @opts[:clean]
      check_source
      copied = copy_files(included)
      removed = remove_stale(included)
      FileUtils.mkdir_p(File.join(dest, 'rmxp3ds'))
      File.write(File.join(dest, 'rmxp3ds', SOURCE_FILE), "#{@game.dir}\n")
      preload_paths = install_preloads(patches)
      File.write(File.join(dest, 'mkxp.json'), mkxp_json(preload_paths))
      @report << "copied #{copied} of #{included.size} files (others unchanged since the last run)"
      @report << "removed #{removed} files no longer in the game" if removed.positive?
      install_runtime
      File.write(File.join(dest, 'rmxp3ds', 'convert-report.txt'), "#{@report.join("\n")}\n")
      true
    end

    private

    # Package name from the title: ASCII letters and digits; titles that are mostly not ASCII get
    # a short hash of the game directory so that two such games do not share a package.
    def slug(title)
      s = title.to_s.b.downcase.gsub(/[^a-z0-9]+/n, '-').gsub(/\A-|-\z/, '')[0, 40]
      s.length < 4 ? "game-#{Digest::SHA256.hexdigest(@game.dir)[0, 8]}" : s
    end

    # Refuses an output that overlaps the game: the package inside the game, or the game inside
    # the directory the converter writes (OUT/rmxp3ds), symbolic links resolved.
    def check_paths
      out = real_path(@opts[:out])
      game = File.join(@game.dir, '')
      writes = File.join(out, 'rmxp3ds', '')
      if File.join(out, '').start_with?(game) || game.start_with?(writes)
        raise ConvertError, '--out overlaps the game directory (the package must be outside the game, and the ' \
                            'game outside OUT/rmxp3ds)'
      end
    end

    # realpath of the deepest existing parent, plus the rest of the path.
    def real_path(path)
      path = File.expand_path(path)
      rest = []
      until File.exist?(path) || path == File.dirname(path)
        rest.unshift(File.basename(path))
        path = File.dirname(path)
      end
      File.join(File.realpath(path), *rest)
    end

    # A package directory belongs to one game: refuse another game's package unless --clean.
    def check_source
      marker = File.join(dest, 'rmxp3ds', SOURCE_FILE)
      return unless File.file?(marker)
      source = File.read(marker).strip
      return if source == @game.dir
      raise ConvertError, "#{dest} holds a package of #{source}; choose another --id or use --clean"
    end

    def include?(rel)
      parts = rel.split('/')
      return false if parts.size > 1 && EXCLUDE_DIRS.include?(parts.first.downcase)
      name = parts.last.downcase
      return false if parts.size == 1 && EXCLUDE_NAMES.include?(name)
      return false if %w[thumbs.db desktop.ini .ds_store].include?(name) || name.start_with?('._')
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
      if dir && patches.empty?
        raise ConvertError, "patch set #{dir} of profile #{@game.profile[:id]}: no *.rb files" if set == 'auto'
        raise ArgumentsError, "--patch-set #{dir}: no *.rb files"
      end
      list = patches.map { |p| [p, "rmxp3ds/patches/#{File.basename(p)}"] }
      Array(@opts[:preloads]).each_with_index do |p, i|
        raise ArgumentsError, "--preload #{p}: not found" unless File.file?(p)
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

    # Deletes files of an earlier run that are no longer in the game (or now left out). Our own
    # files (mkxp.json, rmxp3ds/) stay. Returns the count.
    def remove_stale(included)
      keep = included.map(&:downcase).to_h { |f| [f, true] }
      stale = Dir.glob('**/*', File::FNM_DOTMATCH, base: dest).select do |f|
        next false if f == 'mkxp.json' || f == 'rmxp3ds' || f.start_with?('rmxp3ds/')
        File.file?(File.join(dest, f)) && !keep[f.downcase]
      end
      stale.each { |f| File.delete(File.join(dest, f)) }
      stale.size
    end

    # Same size and modification time (seconds): unchanged. An edit within the same second that
    # keeps the size is not seen; --clean copies everything.
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
      r << (@dry_run ? "package (dry run, nothing written): rmxp3ds/games/#{@id}/" : "package: #{dest} (SD card: rmxp3ds/games/#{@id}/)")
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
        if patches.none? { |_src, rel| rel.start_with?('rmxp3ds/patches/') }
          large.select { |f, _iw, ih| f.downcase.start_with?('graphics/tilesets/') && ih > RGSS_TILESET_HEIGHT }.each do |f, _iw, ih|
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
