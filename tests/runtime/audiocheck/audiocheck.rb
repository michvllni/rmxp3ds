# SPDX-License-Identifier: GPL-3.0-or-later
# Audio check for the 3DS runtime (mkxp-z-3ds, run as customScript): plays the synthetic sounds
# of make-assets.sh through the RGSS Audio module and follows the BGM/BGS positions
# (Audio.bgm_pos, seconds into the file) to see that streams advance, loop, pause for the ME,
# fade, start at a position and change speed with the pitch. SE (Ogg, 8 and 16 bit WAV) must
# play without errors, also more at once than there are channels; a missing file raises, a
# MIDI file is skipped. Timing uses the clock, not frames (Azahar may run slower than 60 FPS).
# Needs ndsp (sdmc:/3ds/dspfirm.cdc on the console). Result in sdmc:/rmxp3ds/test/audio.txt
# (details audio-results.txt).
results = []
Dir.mkdir('sdmc:/rmxp3ds/test') unless Dir.exist?('sdmc:/rmxp3ds/test')
log_path = 'sdmc:/rmxp3ds/test/audio-results.txt'
log_line = lambda do |text|
  File.open(log_path, 'a') { |f| f.puts(text) }
  $stderr.puts(text)
end
File.write(log_path, "RMXP3DS_TEST audio RUNNING\n")
check = lambda do |name, ok, info = nil|
  results << format('check %s %s%s', name, ok ? 'ok' : 'FAILED', info ? " (#{info})" : '')
  log_line.call(results.last)
end
# Draws frames for `sec` seconds of clock time.
wait = lambda do |sec|
  t = Time.now
  Graphics.update while Time.now - t < sec
end
fmt = ->(x) { format('%.3f', x) }

begin
  # BGM streams: the position advances.
  Audio.bgm_play('Audio/BGM/tone', 80, 100)
  wait.call(0.3)
  p1 = Audio.bgm_pos
  wait.call(0.3)
  p2 = Audio.bgm_pos
  check.call('bgm_streams', p1 > 0.05 && p2 > p1 + 0.1, "#{fmt.(p1)} -> #{fmt.(p2)}")

  # LOOPSTART/LOOPLENGTH: after 2.5 s of a 2 s file it plays inside the loop (0.5 .. 1.5 s).
  wait.call(1.9)
  p3 = Audio.bgm_pos
  check.call('bgm_loops', p3 >= 0.45 && p3 <= 1.6, fmt.(p3))

  # The same file again with another volume continues (upstream: only the volume changes).
  Audio.bgm_play('Audio/BGM/tone', 60, 100)
  wait.call(0.1)
  p4 = Audio.bgm_pos
  check.call('bgm_same_file_continues', p4 >= 0.4, fmt.(p4))

  # The ME pauses the BGM (200 ms fade out), then the BGM continues.
  Audio.me_play('Audio/ME/fanfare')
  wait.call(0.4)
  a = Audio.bgm_pos
  wait.call(0.2)
  b = Audio.bgm_pos
  check.call('me_pauses_bgm', a > 0 && (b - a).abs < 0.02, "#{fmt.(a)} -> #{fmt.(b)}")
  wait.call(0.6) # the 0.8 s ME has ended
  c = Audio.bgm_pos
  wait.call(0.3)
  d = Audio.bgm_pos
  adv = d - c
  adv += 1.0 if adv < 0 # wrapped inside the 1 s loop
  check.call('bgm_resumes_after_me', adv > 0.1 && adv < 0.6, "#{fmt.(c)} -> #{fmt.(d)}")

  # Fade out ends the BGM.
  Audio.bgm_fade(300)
  wait.call(0.6)
  check.call('bgm_fade_stops', Audio.bgm_pos == 0, fmt.(Audio.bgm_pos))

  # A start position (seconds).
  Audio.bgm_play('Audio/BGM/tone', 100, 100, 1.0)
  wait.call(0.2)
  p5 = Audio.bgm_pos
  check.call('bgm_start_position', p5 >= 1.0 && p5 < 1.5, fmt.(p5))
  Audio.bgm_stop
  check.call('bgm_stop', Audio.bgm_pos == 0, fmt.(Audio.bgm_pos))

  # Pitch: 150 % plays three times as fast as 50 %.
  Audio.bgm_play('Audio/BGM/tone', 100, 50)
  wait.call(0.5)
  slow = Audio.bgm_pos
  Audio.bgm_play('Audio/BGM/tone', 100, 150)
  wait.call(0.5)
  fast = Audio.bgm_pos
  Audio.bgm_stop
  ratio = slow > 0 ? fast / slow : 0
  check.call('bgm_pitch', ratio > 2.0 && ratio < 4.0, "#{fmt.(slow)} / #{fmt.(fast)}")

  # BGS without loop comments loops from the start.
  Audio.bgs_play('Audio/BGS/short', 50)
  wait.call(0.8)
  q = Audio.bgs_pos
  check.call('bgs_loops', q > 0 && q < 0.5, fmt.(q))
  Audio.bgs_fade(100)

  # SE: Ogg, 8 and 16 bit WAV; then 20 at once (more than the 8 channels).
  se_ok = true
  begin
    Audio.se_play('Audio/SE/beep', 80)
    Audio.se_play('Audio/SE/click', 80)
    Audio.se_play('Audio/SE/click16', 80, 120)
    wait.call(0.2)
    20.times { |i| Audio.se_play(%w[Audio/SE/beep Audio/SE/click Audio/SE/click16][i % 3], 60, 80 + i * 3) }
    wait.call(0.3)
    Audio.se_stop
  rescue Exception => e
    se_ok = false
    se_err = "#{e.class}: #{e.message}"
  end
  check.call('se_play', se_ok, se_err)

  # A missing file raises (as upstream mkxp-z and RGSS).
  raised = begin
    Audio.se_play('Audio/SE/not_there')
    false
  rescue StandardError
    true
  end
  check.call('missing_file_raises', raised)

  # MIDI cannot play on the 3DS: skipped without an error; next to an Ogg of the same name the
  # Ogg plays.
  midi_err = nil
  begin
    Audio.bgm_play('Audio/BGM/song')
  rescue Exception => e
    midi_err = "#{e.class}: #{e.message}"
  end
  wait.call(0.2)
  check.call('midi_skipped', midi_err.nil? && Audio.bgm_pos == 0, midi_err || fmt.(Audio.bgm_pos))
  Audio.bgm_play('Audio/BGM/both')
  wait.call(0.3)
  check.call('ogg_beside_midi', Audio.bgm_pos > 0.1, fmt.(Audio.bgm_pos))
  Audio.bgm_stop
rescue Exception => e
  check.call('exception', false, "#{e.class}: #{e.message} @ #{e.backtrace&.first}")
end
ok = results.none? { |l| l.include?('FAILED') }
line = "RMXP3DS_TEST audio #{ok ? 'PASS' : 'FAIL'} checks=#{results.size}\n"
log_line.call(line.chomp)
File.write('sdmc:/rmxp3ds/test/audio.txt', line)
