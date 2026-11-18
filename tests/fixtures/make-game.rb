#!/usr/bin/env ruby
# SPDX-License-Identifier: GPL-3.0-or-later
#
# SYNOPSIS
#   tests/fixtures/make-game.rb [--out DIR] [--events N]
#
# DESCRIPTION
#   Writes a synthetic game directory for the M2 pipeline test (tools/m2): DIR/Data/Scripts.rxdata
#   in RGSS1's format (Marshal array of [id, name, zlib-deflated source]) with one section per
#   file in tools/m2/synthetic/ (name: the file name without number prefix and extension,
#   capitalized; "90_main.rb" becomes "Main"), and DIR/Data/Map001.rxdata from make-rxdata.rb's
#   generator. All content is generated from this repository; no game content.
#
# OPTIONS
#   --out DIR    output directory (default: tests/fixtures/out/synthetic-game)
#   --events N   events on the map (default: 60)
#   -h, --help   show this help
#
# EXAMPLE
#   ruby tests/fixtures/make-game.rb --out /tmp/synthetic-game
require 'optparse'
require 'zlib'
require 'fileutils'
require_relative '../../tools/bench/romfs/rgss_stubs'

opts = { out: File.expand_path('out/synthetic-game', __dir__), events: 60 }
parser = OptionParser.new do |o|
  o.banner = File.read(__FILE__)[/^# SYNOPSIS.*?^# EXAMPLE\n#[^\n]*\n/m].gsub(/^# ?/, '')
  o.on('--out DIR') { |v| opts[:out] = v }
  o.on('--events N', Integer) { |v| opts[:events] = v }
  o.on('-h', '--help') { puts o.banner; exit }
end
begin
  parser.parse!
rescue OptionParser::ParseError => e
  warn e.message
  warn parser.banner
  exit 2
end

data = File.join(opts[:out], 'Data')
FileUtils.mkdir_p(data)
files = Dir[File.expand_path('../../tools/m2/synthetic/*.rb', __dir__)].sort
abort 'make-game.rb: no sections in tools/m2/synthetic' if files.empty?
sections = files.each_with_index.map do |f, i|
  name = File.basename(f, '.rb').sub(/\A\d+_/, '').capitalize
  [1000 + i, name, Zlib::Deflate.deflate(File.read(f))]
end
File.binwrite(File.join(data, 'Scripts.rxdata'), Marshal.dump(sections))
map = RGSSStubs.synthetic_map(40, 30, opts[:events], 1)
File.binwrite(File.join(data, 'Map001.rxdata'), Marshal.dump(map))
puts "#{opts[:out]}: #{sections.size} script sections (#{sections.map { |s| s[1] }.join(', ')}), " \
     "Map001 with #{opts[:events]} events"
