#!/usr/bin/env ruby
# SPDX-License-Identifier: GPL-3.0-or-later
#
# SYNOPSIS
#   tests/runtime/titlecheck/make-assets.rb --out-dir DIR
#
# DESCRIPTION
#   Writes the synthetic images of the title check (no game or RTP content):
#     DIR/title.png       640x480 RGB: horizontal red ramp (x * 255 / 639), vertical green ramp
#                         (y * 255 / 479), blue 64
#     DIR/windowskin.png  192x128 RGBA in the RGSS1 windowskin layout: background (0,0,128,128)
#                         opaque (40, 60, 160); frame (128,0,64,64) a 4 px white border with a
#                         transparent center; cursor (128,64,32,32) white, 2 px opaque border,
#                         inside alpha 96; everything else transparent
#   PNGs are written with Zlib only (no gems).
#
# OPTIONS
#   --out-dir DIR   output directory (created if missing)
#   -h, --help      show this help
#
# EXAMPLE
#   ruby tests/runtime/titlecheck/make-assets.rb --out-dir build/titlecheck
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
write_png(File.join(out_dir, 'title.png'), 640, 480) do |x, y|
  [x * 255 / 639, y * 255 / 479, 64, 255]
end
write_png(File.join(out_dir, 'windowskin.png'), 192, 128) do |x, y|
  if x < 128
    [40, 60, 160, 255]
  elsif y < 64
    fx = x - 128
    border = fx < 4 || fx >= 60 || y < 4 || y >= 60
    border ? [255, 255, 255, 255] : [0, 0, 0, 0]
  elsif y < 96 && x < 160
    cx = x - 128
    cy = y - 64
    edge = cx < 2 || cx >= 30 || cy < 2 || cy >= 30
    [255, 255, 255, edge ? 255 : 96]
  else
    [0, 0, 0, 0]
  end
end
