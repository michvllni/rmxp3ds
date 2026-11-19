# SPDX-License-Identifier: GPL-3.0-or-later
# Host tests of convert/rmxp3ds-convert with synthetic games (tests/fixtures/make-rmxp-game.rb).
# Run: ruby tests/convert/convert_test.rb
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'zlib'
require_relative '../../convert/lib/rmxp3ds/package'

class ConvertTest < Minitest::Test
  REPO = File.expand_path('../..', __dir__)
  CONVERT = File.join(REPO, 'convert/rmxp3ds-convert')
  MAKE_GAME = File.join(REPO, 'tests/fixtures/make-rmxp-game.rb')

  def setup
    @tmp = Dir.mktmpdir('rmxp3ds-convert-test')
    @game = File.join(@tmp, 'game')
    @out = File.join(@tmp, 'sd')
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  def make_game(*args)
    _o, e, s = Open3.capture3(RbConfig.ruby, MAKE_GAME, '--out', @game, *args)
    assert s.success?, e
  end

  def convert(*args)
    Open3.capture3(RbConfig.ruby, CONVERT, '--game', @game, '--out', @out, *args)
  end

  def pkg(rel = '')
    File.join(@out, 'rmxp3ds/games/t', rel)
  end

  def test_package_layout_and_report
    make_game
    runtime = File.join(@tmp, 'mkxp-z.3dsx')
    File.write(runtime, 'app')
    out, err, st = convert('--id', 't', '--patch-set', File.join(REPO, 'tests/convert/patches'), '--runtime', runtime)
    assert st.success?, err + out
    assert File.file?(pkg('Data/Scripts.rxdata'))
    assert File.file?(pkg('Graphics/Pictures/rmxp3ds-test.png'))
    %w[Game.exe RGSS102E.dll Game.rxproj Audio/desktop.ini].each { |f| refute File.exist?(pkg(f)), f }
    conf = File.read(pkg('mkxp.json'))
    assert_includes conf, '"framebufferScalingFactor": 0.500000'
    assert_includes conf, '"preloadScript": ["rmxp3ds/patches/00_marker.rb"]'
    assert File.file?(pkg('rmxp3ds/patches/00_marker.rb'))
    assert_equal 'app', File.read(File.join(@out, '3ds/rmxp3ds/mkxp-z.3dsx'))
    assert_includes out, 'profile: rmxp'
    assert_includes out, 'Graphics/Autotiles/rmxp3ds-missing (Tilesets.rxdata #1)'
    assert_includes out, 'Graphics/Tilesets/rmxp3ds-tiles.png: 256x1100'
    assert_includes out, 'left out: Game.exe'
    assert_includes File.read(pkg('rmxp3ds/convert-report.txt')), 'result: OK'
  end

  def test_second_run_copies_only_changes
    make_game
    convert('--id', 't')
    out, _e, st = convert('--id', 't')
    assert st.success?
    assert_includes out, 'copied 0 of 8 files'
  end

  def test_bad_file_name_is_an_error_and_writes_nothing
    make_game('--bad-name')
    out, _e, st = convert('--id', 't')
    assert_equal 1, st.exitstatus
    assert_includes out, 'bad?name.png: the name is not allowed'
    refute File.exist?(pkg)
  end

  def test_out_inside_the_game_is_refused
    make_game
    _o, err, st = Open3.capture3(RbConfig.ruby, CONVERT, '--game', @game, '--out', File.join(@game, 'sd'))
    assert_equal 1, st.exitstatus
    assert_includes err, '--out overlaps the game directory'
  end

  # The game inside OUT/rmxp3ds (e.g. converting a package again into the same SD tree): --clean
  # would delete the game, so it is refused.
  def test_game_inside_the_package_tree_is_refused
    inner = File.join(@out, 'rmxp3ds/games/t')
    _o, e, s = Open3.capture3(RbConfig.ruby, MAKE_GAME, '--out', inner)
    assert s.success?, e
    _o, err, st = Open3.capture3(RbConfig.ruby, CONVERT, '--game', inner, '--out', @out, '--id', 't', '--clean')
    assert_equal 1, st.exitstatus
    assert_includes err, '--out overlaps the game directory'
    assert File.file?(File.join(inner, 'Game.ini'))
  end

  def test_package_of_another_game_is_refused
    make_game
    assert convert('--id', 't')[2].success?
    other = File.join(@tmp, 'other')
    Open3.capture3(RbConfig.ruby, MAKE_GAME, '--out', other)
    _o, err, st = Open3.capture3(RbConfig.ruby, CONVERT, '--game', other, '--out', @out, '--id', 't')
    assert_equal 1, st.exitstatus
    assert_includes err, 'holds a package of'
    _o, _e, st = Open3.capture3(RbConfig.ruby, CONVERT, '--game', other, '--out', @out, '--id', 't', '--clean')
    assert st.success?
  end

  def test_stale_files_are_removed
    make_game
    convert('--id', 't')
    File.delete(File.join(@game, 'Graphics/Pictures/rmxp3ds-test.png'))
    out, _e, st = convert('--id', 't')
    assert st.success?
    assert_includes out, 'removed 1 files'
    refute File.exist?(pkg('Graphics/Pictures/rmxp3ds-test.png'))
    assert File.file?(pkg('mkxp.json'))
  end

  def test_names_differing_in_case_are_an_error
    make_game
    FileUtils.cp(File.join(@game, 'Graphics/Pictures/rmxp3ds-test.png'), File.join(@game, 'Graphics/Pictures/RMXP3DS-test.png'))
    out, _e, st = convert('--id', 't')
    assert_equal 1, st.exitstatus
    assert_includes out, 'names differ only in case'
  end

  def test_name_not_utf8_is_an_error
    make_game
    File.write(File.join(@game, "Graphics/Pictures/caf\xE9.png".b), 'x')
    out, _e, st = convert('--id', 't')
    assert_equal 1, st.exitstatus
    assert_includes out, 'the file name is not UTF-8'
  end

  # Names in the data are UTF-8 bytes; the file index must match them (and fold case).
  def test_non_ascii_names_in_the_data
    make_game
    FileUtils.cp(File.join(@game, 'Graphics/Pictures/rmxp3ds-test.png'), File.join(@game, 'Graphics/Tilesets/Pokémon.png'))
    ts = Class.new { def initialize = (@tileset_name, @autotile_names = 'POKÉMON'.b, ['ÉCRAN']) }
    Object.const_set(:RMXP3DSTilesetProbe, ts)
    File.binwrite(File.join(@game, 'Data/Tilesets.rxdata'), Marshal.dump([nil, RMXP3DSTilesetProbe.new]))
    out, _e, st = convert('--id', 't', '--dry-run')
    assert st.success?
    refute_includes out, 'Graphics/Tilesets/POK'
    assert_includes out, 'Graphics/Autotiles/ÉCRAN (Tilesets.rxdata #1)'
  ensure
    Object.send(:remove_const, :RMXP3DSTilesetProbe) if defined?(RMXP3DSTilesetProbe)
  end

  def test_symlink_outside_the_game_is_left_out
    make_game
    secret = File.join(@tmp, 'secret.txt')
    File.write(secret, 'x')
    File.symlink(secret, File.join(@game, 'Data/link.txt'))
    out, _e, st = convert('--id', 't')
    assert st.success?
    assert_includes out, 'Data/link.txt: symbolic link to a file outside the game, left out'
    refute File.exist?(pkg('Data/link.txt'))
  end

  def test_wrong_arguments
    _o, _e, st = Open3.capture3(RbConfig.ruby, CONVERT, '--out', @out)
    assert_equal 2, st.exitstatus
    make_game
    _o, _e, st = convert('--id', 'a/b')
    assert_equal 2, st.exitstatus
    _o, _e, st = convert('--preload', File.join(@tmp, 'nothing.rb'))
    assert_equal 2, st.exitstatus
  end

  # An Essentials-like script list (synthetic text with the markers the profile looks for).
  def test_essentials_profile
    make_game
    text = "module Settings\n  SCREEN_WIDTH  = 512\n  SCREEN_HEIGHT = 384\nend\n" \
           "module Essentials\n  VERSION = \"21.1\"\nend\n"
    File.binwrite(File.join(@game, 'Data/Scripts.rxdata'), Marshal.dump([[1, 'Settings', Zlib::Deflate.deflate(text)]]))
    out, err, st = convert('--id', 't')
    assert st.success?, err
    assert_includes out, 'profile: essentials-v21'
    assert_includes out, 'screen: 512x384, height used 384'
    assert_includes File.read(pkg('mkxp.json')), '"framebufferScalingFactor": 0.625000'
    assert File.file?(pkg('rmxp3ds/patches/tilemap_renderer.rb'))
  end

  def test_win32api_is_reported
    make_game
    text = "X = Win32API.new('user32', 'GetKeyState', 'i', 'i')\n"
    File.binwrite(File.join(@game, 'Data/Scripts.rxdata'), Marshal.dump([[1, 'Keys', Zlib::Deflate.deflate(text)]]))
    out, _e, st = convert('--id', 't', '--dry-run')
    assert st.success?
    assert_match(/Win32API user32: 1 script\(s\) \(Keys\)/, out)
  end

  # The reader never instantiates classes named in the data, existing ones included.
  def test_marshal_reader
    probe = Class.new do
      def initialize = (@v = 5)
      def marshal_load(_d) = raise('must not be called')
      def _dump(_d) = 'abc'
    end
    Object.const_set(:RMXP3DSLoaderProbe, probe)
    plain = Class.new { def initialize = (@v = [1, 'é', { a: 2.5 }]) }
    Object.const_set(:RMXP3DSPlainProbe, plain)
    raw = RMXP3DS::Data.load(Marshal.dump(RMXP3DSLoaderProbe.new))
    assert_instance_of RMXP3DS::Data::Raw, raw
    assert_equal ['RMXP3DSLoaderProbe', 'abc'], [raw.class_name, raw.raw]
    obj = RMXP3DS::Data.load(Marshal.dump([RMXP3DSPlainProbe.new] * 2))
    assert_same obj[0], obj[1]
    assert_equal 'RMXP3DSPlainProbe', obj[0].class_name
    assert_equal [1, 'é', { 'a' => 2.5 }], obj[0][:v].map { |v| v.is_a?(Hash) ? v.transform_keys(&:to_s) : v }
    assert_equal Encoding::UTF_8, obj[0][:v][1].encoding
    assert_nil RMXP3DS::Data.load(Marshal.dump(nil))
    [0, -1, 122, -124, 255, -256, 2**40, -(2**70), 'x'.b, true].each do |v|
      assert_equal v, RMXP3DS::Data.load(Marshal.dump(v))
    end
    assert_raises(RMXP3DS::Data::FormatError) { RMXP3DS::Data.load("\x04\x08[\x07".b) }
  ensure
    Object.send(:remove_const, :RMXP3DSLoaderProbe) if defined?(RMXP3DSLoaderProbe)
    Object.send(:remove_const, :RMXP3DSPlainProbe) if defined?(RMXP3DSPlainProbe)
  end

  def test_image_sizes
    png = File.join(@tmp, 'a.png')
    File.binwrite(png, "\x89PNG\r\n\x1a\n".b + [13].pack('N') + 'IHDR' + [300, 2000].pack('NN') + "\0" * 9)
    assert_equal [300, 2000], RMXP3DS::Images.size(png)
    bmp = File.join(@tmp, 'a.bmp')
    File.binwrite(bmp, 'BM' + "\0" * 16 + [64, -48].pack('l<l<') + "\0" * 8)
    assert_equal [64, 48], RMXP3DS::Images.size(bmp)
    File.binwrite(bmp, 'BM' + "\0" * 12 + [12, 640, 480].pack('Vvv') + "\0" * 4)
    assert_equal [640, 480], RMXP3DS::Images.size(bmp)
    jpg = File.join(@tmp, 'a.jpg')
    File.binwrite(jpg, "\xFF\xD8\xFF\xE0".b + [4].pack('n') + "\0\0".b + "\xFF\xC0".b + [17].pack('n') +
                       [8, 120, 1300].pack('Cnn') + "\0" * 12)
    assert_equal [1300, 120], RMXP3DS::Images.size(jpg)
  end
end
