#!/usr/bin/env ruby
# SPDX-License-Identifier: GPL-3.0-or-later
#
# SYNOPSIS
#   tests/runtime/tilecheck/make-assets.rb --out-dir DIR
#
# DESCRIPTION
#   Writes the synthetic images of the tile check (native map renderer, docs/DECISIONS.md D17;
#   no game or RTP content):
#     DIR/tileset.png   256x1088 RGBA, 8x34 tiles of 32x32; tile n (row-major) is solid
#                       [(n % 16) * 16 + 8, (n / 16) * 12 + 8, 200, 255]. Taller than 1024 px,
#                       so the runtime keeps it as a CPU "mega" bitmap.
#     DIR/autotile.png  192x128 RGBA, an RMXP block autotile with 2 frames of 96x128; the 16x16
#                       piece c = (x % 96) / 16 + (y / 16) * 6 of frame f is solid
#                       [40 + f * 100, c * 5, 50, 255]
#     DIR/single.png    64x32 RGBA, a single-tile autotile with 2 frames: frame 0 solid
#                       [250, 250, 0, 255], frame 1 solid [0, 250, 250, 255]
#   PNGs are written with Zlib only (no gems).
#
# OPTIONS
#   --out-dir DIR   output directory (created if missing)
#   -h, --help      show this help
#
# EXAMPLE
#   ruby tests/runtime/tilecheck/make-assets.rb --out-dir build/tilecheck
require 'fileutils'
require 'optparse'
require 'zlib'

out_dir = nil
parser = OptionParser.new do |o|
  o.banner = File.read(__FILE__)[/^# SYNOPSIS.*?^# EXAMPLE\n#[^\n]*\n/m].gsub(/^# ?/, '')
  o.on('--out-dir DIR') { |v| out_dir = v }
  o.on('-h', '--help') { puts o.banner; exit }
end
begin
  parser.parse!
rescue OptionParser::ParseError => e
  warn e.message
  warn parser.banner
  exit 2
end
if out_dir.nil?
  warn parser.banner
  exit 2
end

# Returns one PNG chunk (length, type, data, CRC).
def chunk(type, data)
  [data.bytesize].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N')
end

# Writes an 8-bit RGBA PNG; pixel(x, y) returns [r, g, b, a].
def write_png(path, width, height)
  raw = (0...height).map do |y|
    "\0" + (0...width).map { |x| yield(x, y) }.flatten.pack('C*')
  end.join
  png = "\x89PNG\r\n\x1a\n".b
  png << chunk('IHDR', [width, height, 8, 6, 0, 0, 0].pack('NNCCCCC'))
  png << chunk('IDAT', Zlib::Deflate.deflate(raw))
  png << chunk('IEND', '')
  File.binwrite(path, png)
end

FileUtils.mkdir_p(out_dir)
write_png(File.join(out_dir, 'tileset.png'), 256, 1088) do |x, y|
  n = (y / 32) * 8 + (x / 32)
  [(n % 16) * 16 + 8, (n / 16) * 12 + 8, 200, 255]
end
write_png(File.join(out_dir, 'autotile.png'), 192, 128) do |x, y|
  [40 + (x / 96) * 100, ((x % 96) / 16 + (y / 16) * 6) * 5, 50, 255]
end
write_png(File.join(out_dir, 'single.png'), 64, 32) do |x, _y|
  x < 32 ? [250, 250, 0, 255] : [0, 250, 250, 255]
end
