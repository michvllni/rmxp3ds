#!/usr/bin/env ruby
# SPDX-License-Identifier: GPL-3.0-or-later
#
# SYNOPSIS
#   tests/runtime/rendercheck/make-transmap.rb --out FILE
#
# DESCRIPTION
#   Writes the synthetic transition map of the render check: a 64x64 grayscale PNG, row y has
#   the value y * 4 (a vertical gradient), for Graphics.transition with a transition image. No
#   external gems: PNG chunks with Zlib.
#
# OPTIONS
#   --out FILE   output file
#   -h, --help   show this help
#
# EXAMPLE
#   ruby tests/runtime/rendercheck/make-transmap.rb --out build/trans-map.png
require 'optparse'
require 'zlib'

out = nil
parser = OptionParser.new do |o|
  o.banner = File.read(__FILE__)[/^# SYNOPSIS.*?^# EXAMPLE\n#[^\n]*\n/m].gsub(/^# ?/, '')
  o.on('--out FILE') { |v| out = v }
  o.on('-h', '--help') { puts o.banner; exit }
end
begin
  parser.parse!
rescue OptionParser::ParseError => e
  warn e.message
  warn parser.banner
  exit 2
end
if out.nil?
  warn parser.banner
  exit 2
end

# Returns one PNG chunk (length, type, data, CRC).
def chunk(type, data)
  [data.bytesize].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N')
end

size = 64
# filter byte 0 per row, then one gray byte per pixel
raw = (0...size).map { |y| "\0" + ([y * 4] * size).pack('C*') }.join
png = "\x89PNG\r\n\x1a\n".b
png << chunk('IHDR', [size, size, 8, 0, 0, 0, 0].pack('NNCCCCC')) # 8-bit grayscale
png << chunk('IDAT', Zlib::Deflate.deflate(raw))
png << chunk('IEND', '')
File.binwrite(out, png)
