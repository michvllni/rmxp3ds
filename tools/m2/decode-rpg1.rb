#!/usr/bin/env ruby
# SPDX-License-Identifier: GPL-3.0-or-later
#
# SYNOPSIS
#   tools/m2/decode-rpg1.rb [--out FILE]
#
# DESCRIPTION
#   Writes mkxp-z's RGSS1 RPG module (RPG::Cache, RPG::Sprite, the RPG data classes) as Ruby
#   source, decoded from the runtime's runtime/binding/module_rpg1.rb.xxd (a C byte array that
#   mkxp-z compiles in). The headless harness loads it like mkxp-z does for RGSS1 games. The
#   output is mkxp-z code (GPL-2.0-or-later) and is generated, not stored in this repository.
#
# OPTIONS
#   --out FILE   output file (default: build/m2/rpg1.rb)
#   -h, --help   show this help
#
# EXAMPLE
#   ruby tools/m2/decode-rpg1.rb --out /tmp/rpg1.rb
require 'optparse'
require 'fileutils'

root = File.expand_path('../..', __dir__)
opts = { out: File.join(root, 'build/m2/rpg1.rb') }
OptionParser.new do |o|
  o.banner = File.read(__FILE__)[/^# SYNOPSIS.*?^# EXAMPLE\n#[^\n]*\n/m].gsub(/^# ?/, '')
  o.on('--out FILE') { |v| opts[:out] = v }
  o.on('-h', '--help') { puts o.banner; exit }
end.parse!

src = File.read(File.join(root, 'runtime/binding/module_rpg1.rb.xxd'))
len = src[/module_rpg1_len\s*=\s*(\d+)/, 1] or abort 'decode-rpg1.rb: module_rpg1_len not found'
body = src[/module_rpg1\[\]\s*=\s*\{(.*?)\}/m, 1] or abort 'decode-rpg1.rb: byte array not found'
bytes = body.scan(/0x\h\h/).map(&:hex).pack('C*')
abort "decode-rpg1.rb: #{bytes.bytesize} bytes, expected #{len} (+ NUL)" if bytes.bytesize < len.to_i
FileUtils.mkdir_p(File.dirname(opts[:out]))
File.binwrite(opts[:out], bytes[0, len.to_i])
puts "#{opts[:out]}: #{len} bytes"
