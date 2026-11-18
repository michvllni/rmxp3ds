# SPDX-License-Identifier: GPL-3.0-or-later
# Hardware run 3 driver (mkxp-z-3ds customScript, game directory sdmc:/rmxp3ds/game): runs the
# engine, render and title checks in one process (each writes its own result file to
# sdmc:/rmxp3ds/test), then on the title scene
#   1. measures frame times at the RGSS1 frame rate (40) and uncapped (Graphics.frame_rate 120),
#   2. keeps running for HOLD seconds (default 60) so HOME and sleep mode can be tried; gaps
#      between frames show the suspensions,
# and writes everything to sdmc:/rmxp3ds/test/hw3.txt. Progress and instructions appear on the
# bottom screen. sdmc:/rmxp3ds/test/hw3-hold.txt (seconds) overrides the hold time; 0 skips it.
out = []
log = lambda do |line|
  out << line
  $stderr.puts line
end
say = ->(text) { print text } # bottom screen console (non-blocking message box)

CHECKS = { 'enginecheck' => 'mkxp', 'rendercheck' => 'render', 'titlecheck' => 'title' }.freeze
CHECKS.each do |name, result_name|
  say.call("hw3: #{name} ...")
  result = "sdmc:/rmxp3ds/test/#{result_name}.txt"
  File.delete(result) if File.exist?(result) # no stale result from an earlier run
  t0 = System.uptime
  begin
    load "#{name}.rb"
  rescue Exception => e
    log.call("#{name}: exception #{e.class}: #{e.message}")
  end
  log.call(format('%-12s %s (%.1f s)', name, File.exist?(result) ? File.read(result).strip : 'no result', System.uptime - t0))
end

scene = $rmxp3ds_title_scene
win = scene && scene[1]
measure = lambda do |frames|
  times = []
  frames.times do
    t = System.uptime
    win&.update
    Graphics.update
    times << System.uptime - t
  end
  times.sort!
  avg = times.sum / times.size
  format('avg %.2f ms (%.1f fps), median %.2f ms, p95 %.2f ms, max %.2f ms', avg * 1000, 1.0 / avg,
         times[times.size / 2] * 1000, times[(times.size * 0.95).to_i] * 1000, times.last * 1000)
end
say.call('hw3: measuring frame times ...')
Graphics.frame_rate = 40
measure.call(40) # settle
log.call("title scene @40:   #{measure.call(400)}")
Graphics.frame_rate = 120
log.call("title scene @120:  #{measure.call(400)}")
Graphics.frame_rate = 40

hold = 60
hold_file = 'sdmc:/rmxp3ds/test/hw3-hold.txt'
hold = File.read(hold_file).to_i if File.exist?(hold_file)
if hold > 0
  say.call("hw3: #{hold} s to test HOME and sleep:\n- press HOME, wait 5 s, return to the app\n- close the lid, wait 5 s, open it\nThe app keeps running and saves the results afterwards.")
  gaps = []
  t_end = System.uptime + hold
  last = System.uptime
  frames = 0
  while System.uptime < t_end
    win&.update
    Graphics.update
    now = System.uptime
    gaps << format('%.1f s after %d frames', now - last, frames) if now - last > 0.5
    last = now
    frames += 1
  end
  log.call("hold: #{frames} frames in #{hold} s; pauses > 0.5 s: #{gaps.empty? ? 'none' : gaps.join(', ')}")
end

passed = out.count { |l| l.include?(' PASS ') }
line = "RMXP3DS_TEST hw3 #{passed == 3 ? 'PASS' : 'FAIL'} checks_passed=#{passed}/3\n"
File.write('sdmc:/rmxp3ds/test/hw3.txt', line + out.join("\n") + "\n")
say.call("hw3: done (#{passed}/3 checks passed). Results: sdmc:/rmxp3ds/test/hw3.txt")
120.times { Graphics.update }
