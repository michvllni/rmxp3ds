#!/usr/bin/env ruby
# SPDX-License-Identifier: GPL-3.0-or-later
#
# SYNOPSIS
#   tests/fixtures/make-rmxp-game.rb --out DIR [--bad-name]
#
# DESCRIPTION
#   Writes a small synthetic RPG Maker XP game for the converter tests (tests/convert): Game.ini,
#   Data/Scripts.rxdata with one section "Main" (tests/convert/game_check.rb), Data/MapInfos,
#   Map001 (20x15, make-rxdata.rb's generator), Tilesets.rxdata (tileset "rmxp3ds-tiles", 256x1100
#   so it is over the texture limit; autotile "rmxp3ds-missing" that does not exist), System.rxdata,
#   Graphics/Pictures/rmxp3ds-test.png (64x32, color 200,40,80) and PC-only files the converter
#   must leave out (Game.exe, RGSS102E.dll, mkxp.json, Game.rxproj, Audio/desktop.ini, all dummy
#   text). Everything is generated here; no game content.
#
# OPTIONS
#   --out DIR    output directory (replaced)
#   --bad-name   also write Graphics/Pictures/bad?name.png (not allowed on FAT32)
#   -h, --help   show this help
#
# EXAMPLE
#   ruby tests/fixtures/make-rmxp-game.rb --out build/convert/game
require 'optparse'
require 'zlib'
require 'fileutils'
require_relative '../../tools/bench/romfs/rgss_stubs'

module RPG
  class Tileset
    attr_accessor :id, :name, :tileset_name, :autotile_names, :panorama_name, :panorama_hue,
                  :fog_name, :fog_hue, :fog_opacity, :fog_blend_type, :fog_zoom, :fog_sx, :fog_sy,
                  :battleback_name, :passages, :priorities, :terrain_tags
  end

  class MapInfo
    attr_accessor :name, :parent_id, :order, :expanded, :scroll_x, :scroll_y
  end

  class System
    attr_accessor :windowskin_name, :title_name, :gameover_name, :battle_transition
  end
end

opts = {}
parser = OptionParser.new do |o|
  o.banner = File.read(__FILE__)[/^# SYNOPSIS.*?^# EXAMPLE\n#[^\n]*\n/m].gsub(/^# ?/, '')
  o.on('--out DIR') { |v| opts[:out] = v }
  o.on('--bad-name') { opts[:bad_name] = true }
  o.on('-h', '--help') { puts o.banner; exit }
end
begin
  parser.parse!
  raise OptionParser::MissingArgument, '--out DIR' unless opts[:out]
rescue OptionParser::ParseError => e
  warn e.message
  warn parser.banner
  exit 2
end

def chunk(type, data)
  [data.bytesize].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N')
end

def write_png(path, width, height)
  raw = (0...height).map { |y| "\0" + (0...width).map { |x| yield(x, y) }.flatten.pack('C*') }.join
  png = "\x89PNG\r\n\x1a\n".b
  png << chunk('IHDR', [width, height, 8, 6, 0, 0, 0].pack('NNCCCCC'))
  png << chunk('IDAT', Zlib::Deflate.deflate(raw))
  png << chunk('IEND', '')
  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, png)
end

out = opts[:out]
FileUtils.rm_rf(out)
data = File.join(out, 'Data')
FileUtils.mkdir_p(data)
File.write(File.join(out, 'Game.ini'), "[Game]\r\nLibrary=RGSS102E.dll\r\nScripts=Data\\Scripts.rxdata\r\n" \
                                        "Title=rmxp3ds convert test\r\nRTP1=\r\n")
check = File.read(File.expand_path('../convert/game_check.rb', __dir__))
File.binwrite(File.join(data, 'Scripts.rxdata'), Marshal.dump([[1, 'Main', Zlib::Deflate.deflate(check)]]))
info = RPG::MapInfo.new
info.name = 'Test'
info.parent_id = 0
info.order = 1
File.binwrite(File.join(data, 'MapInfos.rxdata'), Marshal.dump({ 1 => info }))
File.binwrite(File.join(data, 'Map001.rxdata'), Marshal.dump(RGSSStubs.synthetic_map(20, 15, 5, 7)))
ts = RPG::Tileset.new
ts.id = 1
ts.name = 'Test'
ts.tileset_name = 'rmxp3ds-tiles'
ts.autotile_names = ['rmxp3ds-missing', '', '', '', '', '', '']
ts.panorama_name = ts.fog_name = ts.battleback_name = ''
File.binwrite(File.join(data, 'Tilesets.rxdata'), Marshal.dump([nil, ts]))
sys = RPG::System.new
sys.windowskin_name = sys.title_name = sys.gameover_name = sys.battle_transition = ''
File.binwrite(File.join(data, 'System.rxdata'), Marshal.dump(sys))
write_png(File.join(out, 'Graphics/Pictures/rmxp3ds-test.png'), 64, 32) { [200, 40, 80, 255] }
write_png(File.join(out, 'Graphics/Tilesets/rmxp3ds-tiles.png'), 256, 1100) { |x, y| [x, y & 255, 0, 255] }
write_png(File.join(out, 'Graphics/Pictures/bad?name.png'), 4, 4) { [0, 0, 0, 255] } if opts[:bad_name]
{ 'Game.exe' => 'dummy', 'RGSS102E.dll' => 'dummy', 'mkxp.json' => '{}', 'Game.rxproj' => 'RPGXP 1.02',
  'Audio/desktop.ini' => '[.ShellClassInfo]' }.each do |rel, text|
  FileUtils.mkdir_p(File.dirname(File.join(out, rel)))
  File.write(File.join(out, rel), text)
end
puts "#{out}: synthetic RPG Maker XP game"
