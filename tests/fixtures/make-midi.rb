#!/usr/bin/env ruby
# SPDX-License-Identifier: GPL-3.0-or-later
#
# SYNOPSIS
#   tests/fixtures/make-midi.rb --out-dir DIR
#
# DESCRIPTION
#   Writes synthetic MIDI test files (no game content):
#     DIR/song.mid   Standard MIDI File, format 1, 480 ticks per quarter, two tracks. Track 0:
#                    tempo 500000 us/quarter at tick 0, 250000 at tick 960. Track 1: note 69
#                    on at 0, controller 111 (RPG Maker loop start) at 480, notes 72 and 76
#                    after it (running status), all off at 1920, end of track.
#                    Timing: loop start 0.5 s, end 1.5 s.
#     DIR/test.sf2   SoundFont 2.01 with one preset (bank 0, program 0) playing a looped 441 Hz
#                    sine (22050 Hz, 16 bit) for every key: enough for FluidSynth to render.
#
# OPTIONS
#   --out-dir DIR   output directory (created if missing)
#   -h, --help      show this help
#
# EXAMPLE
#   ruby tests/fixtures/make-midi.rb --out-dir build/midi
require 'fileutils'
require 'optparse'

module MakeMidi
  module_function

  def vlq(n)
    bytes = [n & 0x7F]
    bytes.unshift((n >>= 7) & 0x7F | 0x80) while n > 0x7F
    bytes.pack('C*')
  end

  def track(events)
    body = events.map { |delta, data| vlq(delta) + data.pack('C*') }.join + vlq(0) + [0xFF, 0x2F, 0].pack('C*')
    'MTrk' + [body.bytesize].pack('N') + body
  end

  def midi
    t0 = track([[0, [0xFF, 0x51, 3, 0x07, 0xA1, 0x20]], [960, [0xFF, 0x51, 3, 0x03, 0xD0, 0x90]]])
    t1 = track([
                 [0, [0x90, 69, 100]],
                 [480, [0xB0, 111, 0]],
                 [0, [0x90, 72, 100]],
                 [240, [76, 100]], # running status (note on)
                 [1200, [0x80, 69, 0]],
                 [0, [0x80, 72, 0]],
                 [0, [0x80, 76, 0]]
               ])
    'MThd' + [6, 1, 2, 480].pack('Nnnn') + t0 + t1
  end

  def chunk(id, data)
    data += "\0" if data.bytesize.odd?
    id + [data.bytesize].pack('V') + data
  end

  def list(type, *chunks)
    chunk('LIST', type + chunks.join)
  end

  def name20(s)
    s.ljust(20, "\0")[0, 20]
  end

  def sf2
    rate = 22_050
    n = 2000 # 40 periods of 441 Hz
    samples = Array.new(n) { |i| (Math.sin(2 * Math::PI * 441 * i / rate) * 12_000).round }
    smpl = (samples + [0] * 46).pack('s<*')
    info = list('INFO', chunk('ifil', [2, 1].pack('vv')), chunk('isng', "EMU8000\0"), chunk('INAM', "rmxp3ds test\0"))
    sdta = list('sdta', chunk('smpl', smpl))
    phdr = [name20('sine'), 0, 0, 0, 0, 0, 0].pack('a20vvvVVV') + [name20('EOP'), 0, 0, 1, 0, 0, 0].pack('a20vvvVVV')
    pbag = [0, 0, 1, 0].pack('v4')
    pmod = "\0" * 10
    pgen = [41, 0, 0, 0].pack('v4') # instrument 0, terminal
    inst = [name20('sine'), 0].pack('a20v') + [name20('EOI'), 1].pack('a20v')
    ibag = [0, 0, 2, 0].pack('v4')
    imod = "\0" * 10
    igen = [54, 1, 53, 0, 0, 0].pack('v6') # sampleModes loop, sampleID 0, terminal
    shdr = [name20('sine'), 0, n, 0, n, rate, 69, 0, 0, 1].pack('a20VVVVVCcvv') +
           [name20('EOS'), 0, 0, 0, 0, 0, 0, 0, 0, 0].pack('a20VVVVVCcvv')
    pdta = list('pdta', chunk('phdr', phdr), chunk('pbag', pbag), chunk('pmod', pmod), chunk('pgen', pgen),
                chunk('inst', inst), chunk('ibag', ibag), chunk('imod', imod), chunk('igen', igen),
                chunk('shdr', shdr))
    body = 'sfbk' + info + sdta + pdta
    'RIFF' + [body.bytesize].pack('V') + body
  end
end

if $PROGRAM_NAME == __FILE__
  out = nil
  parser = OptionParser.new do |o|
    o.banner = File.read(__FILE__)[/^# SYNOPSIS.*?^# EXAMPLE\n#[^\n]*\n/m].gsub(/^# ?/, '')
    o.on('--out-dir DIR') { |v| out = v }
    o.on('-h', '--help') { puts o.banner; exit }
  end
  begin
    parser.parse!
    raise OptionParser::MissingArgument, '--out-dir' unless out && ARGV.empty?
  rescue OptionParser::ParseError => e
    warn "make-midi.rb: #{e.message}"
    warn parser.banner
    exit 2
  end
  FileUtils.mkdir_p(out)
  File.binwrite(File.join(out, 'song.mid'), MakeMidi.midi)
  File.binwrite(File.join(out, 'test.sf2'), MakeMidi.sf2)
  puts "song.mid and test.sf2 in #{out}"
end
