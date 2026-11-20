# SPDX-License-Identifier: GPL-3.0-or-later
# MIDI for the 3DS: the runtime cannot synthesize MIDI (no FluidSynth on the 3DS), so the
# converter renders every MIDI file of the game to Ogg Vorbis with FluidSynth and the game's
# soundfont, and writes the loop as Vorbis comments LOOPSTART/LOOPLENGTH (samples), which the
# runtime honors. The loop follows mkxp-z's MIDI player (src/audio/midisource.cpp): controller
# 111 (CC111) marks the loop start, the end of the longest track the loop end; without CC111 the
# whole song loops. The reverb tail after the last event is rendered but outside the loop.
require 'open3'
require 'tmpdir'

module RMXP3DS
  module Midi
    RATE = 32_000 # Hz: close to the DSP output rate (32728 Hz); half the decoding work of 64 kHz
    GAIN = '0.5'  # FluidSynth master gain: default 0.2 is quiet next to Ogg BGM; 0.5 is about as loud
                  # (Essentials v21.1: mean -16.9 dB vs -15.3 dB); peaks go through a limiter
    QUALITY = '4' # libvorbis -q:a (about 128 kbit/s stereo)
    TAIL = 2      # seconds rendered after the last event (reverb, release)

    # Song timing: { loop_start:, end: } in seconds, or nil if the file is not a readable
    # Standard MIDI File with a ticks-per-quarter time base.
    def self.timing(path)
      data = File.binread(path)
      return nil unless data.start_with?('MThd') && data.bytesize >= 14
      hlen = data[4, 4].unpack1('N')
      _fmt, ntrks, div = data[8, 6].unpack('n3')
      return nil if div.zero? || div & 0x8000 != 0 # SMPTE time base: not used by RPG Maker games
      tempos = []
      loop_tick = nil
      end_tick = 0
      pos = 8 + hlen
      ntrks.times do
        break unless data[pos, 4] == 'MTrk'
        len = data[pos + 4, 4].unpack1('N')
        start = pos + 8
        pos = start + len
        tick, loop_t = track(data, start, [pos, data.bytesize].min, tempos)
        end_tick = tick if tick > end_tick
        loop_tick = loop_t if loop_t && (loop_tick.nil? || loop_t > loop_tick)
      end
      map = tempo_map(tempos, div)
      { loop_start: loop_tick ? seconds(map, loop_tick) : 0.0, end: seconds(map, end_tick) }
    rescue SystemCallError, IOError
      nil
    end

    # Reads one track: returns [last tick, tick of the last CC111 or nil]; adds tempo changes.
    def self.track(data, pos, stop, tempos)
      tick = 0
      status = nil
      loop_tick = nil
      while pos < stop
        delta, pos = vlq(data, pos)
        tick += delta
        b = data.getbyte(pos) or break
        if b >= 0x80
          status = b
          pos += 1
        elsif status.nil? || status >= 0xF0
          break # running status without a status byte: damaged track
        end
        case status
        when 0xFF
          type = data.getbyte(pos) or break
          len, pos = vlq(data, pos + 1)
          if type == 0x51 && len == 3 && pos + 3 <= stop
            tempos << [tick, (data.getbyte(pos) << 16) | (data.getbyte(pos + 1) << 8) | data.getbyte(pos + 2)]
          end
          pos += len
          break if type == 0x2F
        when 0xF0, 0xF7
          len, pos = vlq(data, pos)
          pos += len
        else
          hi = status & 0xF0
          loop_tick = tick if hi == 0xB0 && data.getbyte(pos) == 111
          pos += (hi == 0xC0 || hi == 0xD0) ? 1 : 2
        end
      end
      [tick, loop_tick]
    end

    def self.vlq(data, pos)
      value = 0
      4.times do
        b = data.getbyte(pos) or return [value, pos]
        pos += 1
        value = (value << 7) | (b & 0x7F)
        return [value, pos] if b < 0x80
      end
      [value, pos]
    end

    # [[tick, seconds at tick, seconds per tick]] from tempo events (default 120 BPM).
    def self.tempo_map(tempos, div)
      map = [[0, 0.0, 0.5 / div]]
      tempos.sort_by(&:first).each do |tick, usec|
        t0, s0, spt = map.last
        sec = s0 + (tick - t0) * spt
        map.pop if tick == t0
        map << [tick, sec, usec / 1e6 / div]
      end
      map
    end

    def self.seconds(map, tick)
      t, sec, spt = map.reverse.find { |m| m[0] <= tick }
      sec + (tick - t) * spt
    end

    # FluidSynth and ffmpeg on PATH? Returns the missing names.
    def self.missing_tools
      %w[fluidsynth ffmpeg].reject do |tool|
        ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? { |d| File.executable?(File.join(d, tool)) }
      end
    end

    # Renders `mid` with `soundfont` to the Ogg Vorbis file `ogg`. Returns nil on success, else
    # an error text.
    def self.render(mid, soundfont, ogg)
      t = timing(mid)
      return 'not a readable MIDI file' unless t
      Dir.mktmpdir('rmxp3ds-midi') do |tmp|
        wav = File.join(tmp, 'song.wav')
        _out, err, st = Open3.capture3('fluidsynth', '-ni', '-q', '-g', GAIN, '-r', RATE.to_s, '-T', 'wav',
                                       '-O', 'float', '-F', wav, soundfont, mid)
        return "fluidsynth failed: #{err.lines.last&.strip}" unless st.success? && File.size?(wav)
        loop_start = (t[:loop_start] * RATE).round
        loop_len = ((t[:end] - t[:loop_start]) * RATE).round
        meta = loop_len.positive? ? ['-metadata', "LOOPSTART=#{loop_start}", '-metadata', "LOOPLENGTH=#{loop_len}"] : []
        _out, err, st = Open3.capture3('ffmpeg', '-loglevel', 'error', '-y', '-i', wav, '-t', format('%.3f', t[:end] + TAIL),
                                       '-af', 'alimiter=limit=0.97:level=disabled:latency=1', '-c:a', 'libvorbis', '-q:a', QUALITY, *meta, ogg)
        return "ffmpeg failed: #{err.lines.last&.strip}" unless st.success?
      end
      nil
    end
  end
end
