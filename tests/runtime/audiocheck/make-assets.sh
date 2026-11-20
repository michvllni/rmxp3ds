#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# SYNOPSIS
#   tests/runtime/audiocheck/make-assets.sh --out-dir DIR
#
# DESCRIPTION
#   Writes the synthetic sounds of the audio check (sine tones made by ffmpeg, no game or RTP
#   content) in the game layout under DIR:
#     Audio/BGM/tone.ogg     2.0 s, 44100 Hz stereo, 440 Hz; Vorbis comments LOOPSTART=22050
#                            LOOPLENGTH=44100 (loops 0.5 s .. 1.5 s)
#     Audio/BGM/both.ogg     1.0 s, 32000 Hz mono, next to both.mid (the runtime skips the MIDI)
#     Audio/BGM/both.mid     a minimal MIDI file (header and one empty track)
#     Audio/BGM/song.mid     the same MIDI alone (not playable on the 3DS: skipped, no error)
#     Audio/BGS/short.ogg    0.5 s, 32000 Hz mono (loops from the start)
#     Audio/ME/fanfare.ogg   0.8 s, 48000 Hz stereo
#     Audio/SE/beep.ogg      0.15 s, 22050 Hz mono
#     Audio/SE/click.wav     0.1 s, 11025 Hz mono, unsigned 8 bit PCM
#     Audio/SE/click16.wav   0.1 s, 22050 Hz stereo, signed 16 bit PCM
#
# OPTIONS
#   --out-dir DIR   output directory (created if missing)
#   -h, --help      show this help
#
# EXAMPLE
#   tests/runtime/audiocheck/make-assets.sh --out-dir build/audiocheck
set -euo pipefail

usage() {
  sed -n '/^# SYNOPSIS/,/^# EXAMPLE/{s/^# \{0,1\}//;p}' "$0"
  sed -n '/^# EXAMPLE/{n;s/^# \{0,1\}//;p}' "$0"
}

out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out-dir) [ $# -ge 2 ] || { usage >&2; exit 2; }; out="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "make-assets.sh: unknown argument $1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -n "$out" ] || { usage >&2; exit 2; }

# tone OUT SECONDS RATE CHANNELS FREQ [extra ffmpeg output options]: writes a sine tone.
tone() {
  local file="$1" secs="$2" rate="$3" ch="$4" freq="$5"
  shift 5
  ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=${freq}:sample_rate=${rate}:duration=${secs}" \
    -ac "$ch" "$@" "$file"
}

mkdir -p "$out/Audio/BGM" "$out/Audio/BGS" "$out/Audio/ME" "$out/Audio/SE"
tone "$out/Audio/BGM/tone.ogg" 2.0 44100 2 440 -c:a libvorbis -metadata LOOPSTART=22050 -metadata LOOPLENGTH=44100
tone "$out/Audio/BGM/both.ogg" 1.0 32000 1 330 -c:a libvorbis
tone "$out/Audio/BGS/short.ogg" 0.5 32000 1 220 -c:a libvorbis
tone "$out/Audio/ME/fanfare.ogg" 0.8 48000 2 660 -c:a libvorbis
tone "$out/Audio/SE/beep.ogg" 0.15 22050 1 880 -c:a libvorbis
tone "$out/Audio/SE/click.wav" 0.1 11025 1 1000 -c:a pcm_u8
tone "$out/Audio/SE/click16.wav" 0.1 22050 2 1200 -c:a pcm_s16le
# MIDI: MThd (format 0, one track, 96 ticks per quarter) and an MTrk with only End of Track.
printf 'MThd\000\000\000\006\000\000\000\001\000\140MTrk\000\000\000\004\000\377\057\000' > "$out/Audio/BGM/song.mid"
cp "$out/Audio/BGM/song.mid" "$out/Audio/BGM/both.mid"
echo "audio check sounds in $out/Audio"
