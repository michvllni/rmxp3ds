#!/usr/bin/env ruby
# SPDX-License-Identifier: GPL-3.0-or-later
#
# SYNOPSIS
#   tools/sdlcheck/make-png.rb --out FILE
#
# DESCRIPTION
#   Writes the 8x8 RGBA test image of tools/sdlcheck (no external gems: PNG chunks with Zlib).
#   Pixel (x, y) = (r, g, b, a) = (x * 32, y * 32, (x * y * 4) & 255, (x + y).odd? ? 128 : 255).
#   main.c checks every pixel against the same formula.
#
# OPTIONS
#   --out FILE   output file
#   -h, --help   show this help
#
# EXAMPLE
#   ruby tools/sdlcheck/make-png.rb --out /tmp/check.png
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
unless out
  warn parser.banner
  exit 2
end

# chunk TYPE DATA: one PNG chunk (length, type, data, CRC over type + data).
def chunk(type, data)
  [data.bytesize].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N')
end

w = h = 8
rows = (0...h).map do |y|
  "\x00".b + (0...w).map { |x| [x * 32, y * 32, (x * y * 4) & 255, (x + y).odd? ? 128 : 255].pack('C4') }.join
end
png = "\x89PNG\r\n\x1a\n".b +
      chunk('IHDR', [w, h, 8, 6, 0, 0, 0].pack('NNC5')) +
      chunk('IDAT', Zlib::Deflate.deflate(rows.join)) +
      chunk('IEND', '')
File.binwrite(out, png)
