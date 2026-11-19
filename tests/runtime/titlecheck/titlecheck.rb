# SPDX-License-Identifier: GPL-3.0-or-later
# Title screen check for the 3DS runtime (mkxp-z-3ds, run as customScript): a synthetic title
# scene in the style of an RPG Maker XP title screen, built only from the RGSS API (no RTP or
# game scripts): a full-screen title sprite, a command window with windowskin, three entries
# and a cursor, faded in and out with Graphics.transition. Images come from make-assets.rb
# (Graphics/Titles/title.png, Graphics/Windowskins/windowskin.png). The screen is read back
# with Graphics.snap_to_bitmap. Result in sdmc:/rmxp3ds/test/title.txt (details
# title-results.txt).
results = []
Dir.mkdir('sdmc:/rmxp3ds/test') unless Dir.exist?('sdmc:/rmxp3ds/test')
log_path = 'sdmc:/rmxp3ds/test/title-results.txt'
# Every line is appended at once (file closed after each), so a crash or freeze keeps what ran.
log_line = lambda do |text|
  File.open(log_path, 'a') { |f| f.puts(text) }
  $stderr.puts(text)
end
File.write(log_path, "RMXP3DS_TEST title RUNNING\n")
check = lambda do |name, ok, info = nil|
  results << format('check %s %s%s', name, ok ? 'ok' : 'FAILED', info ? " (#{info})" : '')
  log_line.call(results.last)
end
rgb = ->(c) { [c.red.round, c.green.round, c.blue.round] }
near = ->(a, b, tol = 4) { a.zip(b).all? { |x, y| (x - y).abs <= tol } }
WIN = { x: 240, y: 288, w: 160, h: 128 }.freeze
ITEMS = ['New Game', 'Continue', 'Shutdown'].freeze

# Builds the scene; returns the objects to dispose.
build = lambda do
  title = Sprite.new
  title.bitmap = Bitmap.new('Graphics/Titles/title.png')
  win = Window.new
  win.windowskin = Bitmap.new('Graphics/Windowskins/windowskin.png')
  win.x = WIN[:x]; win.y = WIN[:y]; win.width = WIN[:w]; win.height = WIN[:h]
  win.contents = Bitmap.new(WIN[:w] - 32, WIN[:h] - 32)
  win.contents.font.color = Color.new(255, 255, 255)
  ITEMS.each_with_index { |t, i| win.contents.draw_text(4, i * 32, WIN[:w] - 40, 32, t) }
  win.cursor_rect.set(0, 32, WIN[:w] - 32, 32) # second entry selected
  win.active = true
  win.z = 10
  [title, win]
end

begin
  Graphics.freeze
  objs = build.call
  Graphics.transition(20)
  30.times { objs[1].update; Graphics.update }
  shot = Graphics.snap_to_bitmap
  # title image: r = x * 255 / 639, g = y * 255 / 479, b = 64
  check.call('title_image', near.call(rgb.call(shot.get_pixel(100, 50)), [40, 27, 64]), rgb.call(shot.get_pixel(100, 50)).inspect)
  check.call('title_left_of_window', near.call(rgb.call(shot.get_pixel(230, 350)), [92, 186, 64]), rgb.call(shot.get_pixel(230, 350)).inspect)
  # window: frame (white border of the skin), background (skin color) next to the first entry
  cx = WIN[:x] + 16
  cy = WIN[:y] + 16
  check.call('window_frame', near.call(rgb.call(shot.get_pixel(WIN[:x] + 1, WIN[:y] + 60)), [255, 255, 255], 8),
             rgb.call(shot.get_pixel(WIN[:x] + 1, WIN[:y] + 60)).inspect)
  check.call('window_background', near.call(rgb.call(shot.get_pixel(cx + 118, cy + 10)), [40, 60, 160], 8),
             rgb.call(shot.get_pixel(cx + 118, cy + 10)).inspect)
  # text of the first entry: white ink over the background
  ink = 0
  (cy + 4...cy + 28).step(2) { |y| (cx + 4...cx + 80).step(2) { |x| ink += 1 if shot.get_pixel(x, y).red > 150 } }
  check.call('entry_text', ink > 20, "#{ink} samples")
  # cursor on the second entry: brighter than the background (it blinks while active)
  cur = rgb.call(shot.get_pixel(cx + 118, cy + 48))
  check.call('cursor', cur[0] > 70 && cur[2] >= 160, cur.inspect)
  shot.dispose
  log_line.call('stage fade out')
  # fade out to black
  Graphics.freeze
  objs.each do |o|
    o.bitmap.dispose if o.respond_to?(:bitmap) && o.bitmap
    if o.is_a?(Window)
      o.windowskin&.dispose
      o.contents&.dispose
    end
    o.dispose
  end
  Graphics.transition(20)
  shot = Graphics.snap_to_bitmap
  # size checked too: get_pixel outside a smaller snapshot also reads black
  check.call('fade_out', shot.width == 640 && rgb.call(shot.get_pixel(320, 240)) == [0, 0, 0],
             "#{shot.width}x#{shot.height} #{rgb.call(shot.get_pixel(320, 240)).inspect}")
  shot.dispose
  log_line.call('stage fade in')
  # back in for the screenshot
  Graphics.freeze
  objs = build.call
  Graphics.transition(20)
rescue Exception => e
  check.call('exception', false, "#{e.class}: #{e.message} @ #{e.backtrace&.first}")
end
ok = results.none? { |l| l.include?('FAILED') }
line = "RMXP3DS_TEST title #{ok ? 'PASS' : 'FAIL'} checks=#{results.size}\n"
log_line.call(line.chomp)
File.write('sdmc:/rmxp3ds/test/title.txt', line)
240.times { objs[1].update if objs; Graphics.update } # keep the scene on screen for the screenshot
$rmxp3ds_title_scene = objs # used by tools/hw3/hw3.rb (frame times on this scene)
