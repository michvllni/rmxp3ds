#!/usr/bin/env ruby
# SPDX-License-Identifier: GPL-3.0-or-later
#
# SYNOPSIS
#   tests/fixtures/make-rxdata.rb [--out FILE] [--events N] [--width W] [--height H] [--seed S]
#
# DESCRIPTION
#   Writes a synthetic RPG Maker XP-style map file (Marshal format 4.8, like Data/MapXXX.rxdata):
#   an RPG::Map with a 3-layer Table and N events, each with pages and event commands. The data
#   is generated, not copied from any game; class layouts follow the public RGSS1 reference
#   (instance variable names only). Used by the 3DS Ruby tests and benchmarks.
#   The same class stubs are defined in tools/bench/romfs/rgss_stubs.rb.
#
# OPTIONS
#   --out FILE   output file (default: tests/fixtures/out/Map001.rxdata)
#   --events N   number of events (default: 60)
#   --width W    map width in tiles (default: 40)
#   --height H   map height in tiles (default: 30)
#   --seed S     random seed (default: 1)
#   -h, --help   show this help
#
# EXAMPLE
#   ruby tests/fixtures/make-rxdata.rb --out /tmp/Map001.rxdata --events 100
require 'optparse'
require 'fileutils'
require_relative '../../tools/bench/romfs/rgss_stubs'

opts = { out: File.expand_path('out/Map001.rxdata', __dir__), events: 60, width: 40, height: 30, seed: 1 }
parser = OptionParser.new do |o|
  o.banner = File.read(__FILE__)[/^# SYNOPSIS.*?^# EXAMPLE\n#[^\n]*\n/m].gsub(/^# ?/, '')
  o.on('--out FILE') { |v| opts[:out] = v }
  o.on('--events N', Integer) { |v| opts[:events] = v }
  o.on('--width W', Integer) { |v| opts[:width] = v }
  o.on('--height H', Integer) { |v| opts[:height] = v }
  o.on('--seed S', Integer) { |v| opts[:seed] = v }
  o.on('-h', '--help') { puts o.banner; exit }
end
begin
  parser.parse!
rescue OptionParser::ParseError => e
  warn e.message
  warn parser.banner
  exit 2
end

map = RGSSStubs.synthetic_map(opts[:width], opts[:height], opts[:events], opts[:seed])
data = Marshal.dump(map)
FileUtils.mkdir_p(File.dirname(opts[:out]))
File.binwrite(opts[:out], data)
puts "#{opts[:out]}: #{data.bytesize} bytes, #{opts[:events]} events, " \
     "#{opts[:width]}x#{opts[:height]}, digest #{RGSSStubs.digest(map)}"
