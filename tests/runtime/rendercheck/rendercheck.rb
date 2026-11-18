# SPDX-License-Identifier: GPL-3.0-or-later
# Render check for the 3DS runtime (mkxp-z-3ds, run as customScript): Bitmap operations on the GPU
# read back with get_pixel (texture layout, render targets, ReadPixels), then a screen scene for the
# screenshot: four colored quadrants (red top left, green top right, blue bottom left, white bottom
# right) over a gray background. Result in sdmc:/rmxp3ds/test/render.txt (details render-results.txt).
results = []
check = lambda do |name, ok, info = nil|
  results << format('check %s %s%s', name, ok ? 'ok' : 'FAILED', info ? " (#{info})" : '')
end
px = ->(c) { [c.red.round, c.green.round, c.blue.round, c.alpha.round] }
RED = Color.new(255, 0, 0); GREEN = Color.new(0, 255, 0); BLUE = Color.new(0, 0, 255)
WHITE = Color.new(255, 255, 255)
begin
  b = Bitmap.new(64, 32)
  b.fill_rect(0, 0, 32, 16, RED)
  b.fill_rect(32, 16, 32, 16, BLUE)
  check.call('fill_top_left', px.call(b.get_pixel(5, 5)) == [255, 0, 0, 255], px.call(b.get_pixel(5, 5)).inspect)
  check.call('fill_bottom_right', px.call(b.get_pixel(40, 20)) == [0, 0, 255, 255], px.call(b.get_pixel(40, 20)).inspect)
  check.call('untouched_transparent', px.call(b.get_pixel(40, 5)) == [0, 0, 0, 0], px.call(b.get_pixel(40, 5)).inspect)
  b.clear_rect(0, 0, 8, 8)
  check.call('clear_rect', px.call(b.get_pixel(2, 2)) == [0, 0, 0, 0] && px.call(b.get_pixel(10, 10)) == [255, 0, 0, 255],
             "#{px.call(b.get_pixel(2, 2)).inspect} #{px.call(b.get_pixel(10, 10)).inspect}")
  d = Bitmap.new(64, 32)
  d.fill_rect(d.rect, WHITE)
  d.blt(0, 0, b, b.rect)
  check.call('blt', px.call(d.get_pixel(12, 5)) == [255, 0, 0, 255] && px.call(d.get_pixel(40, 5)) == [255, 255, 255, 255],
             "#{px.call(d.get_pixel(12, 5)).inspect} #{px.call(d.get_pixel(40, 5)).inspect}")
  t = Bitmap.new(96, 32)
  t.font.size = 20
  t.draw_text(0, 0, 96, 32, 'Abc')
  inked = 0
  (0...32).each { |y| (0...96).each { |x| inked += 1 if t.get_pixel(x, y).alpha > 0 } }
  check.call('draw_text', inked > 50, "#{inked} pixels")

  # Bitmap#blt compositing (bitmapBlit.frag) with opacity: onto transparent and opaque pixels
  near = ->(a, b) { a.zip(b).all? { |x, y| (x - y).abs <= 3 } }
  src = Bitmap.new(16, 16)
  src.fill_rect(src.rect, RED)
  tdst = Bitmap.new(16, 16)
  tdst.blt(0, 0, src, src.rect, 128)
  check.call('blt_transparent_dst', near.call(px.call(tdst.get_pixel(8, 8)), [255, 0, 0, 128]), px.call(tdst.get_pixel(8, 8)).inspect)
  odst = Bitmap.new(16, 16)
  odst.fill_rect(odst.rect, WHITE)
  odst.blt(0, 0, src, src.rect, 128)
  check.call('blt_opaque_dst', near.call(px.call(odst.get_pixel(8, 8)), [255, 127, 127, 255]), px.call(odst.get_pixel(8, 8)).inspect)

  # VRAM pressure: 12 window-sized bitmaps drawn into on the GPU (2 MB each padded, VRAM 6 MB);
  # the first ones must keep their content when they are moved out of VRAM
  big = Array.new(12) do |i|
    bm = Bitmap.new(640, 480)
    bm.fill_rect(0, 0, 64, 64, i.even? ? RED : BLUE)
    bm.draw_text(0, 100, 200, 40, "Bitmap #{i}")
    bm
  end
  big.each { |bm| bm.blt(100, 0, src, src.rect) } # draw into all of them again (evictions)
  firsts = [0, 1, 11].map { |i| px.call(big[i].get_pixel(10, 10)) + px.call(big[i].get_pixel(108, 8)) }
  check.call('vram_pressure', firsts == [[255, 0, 0, 255] * 2, [0, 0, 255, 255, 255, 0, 0, 255], [0, 0, 255, 255, 255, 0, 0, 255]],
             firsts.inspect)
  big.each(&:dispose)

  # Many GPU draws without a frame end (GPU command buffer): 1500 one-pixel blts with opacity
  # (always drawn on the GPU, two draws each), then a fill of the render target
  many = Bitmap.new(100, 15)
  gsrc = Bitmap.new(1, 1)
  gsrc.fill_rect(gsrc.rect, GREEN)
  1500.times { |i| many.blt(i % 100, i / 100, gsrc, gsrc.rect, 254) }
  many.fill_rect(99, 14, 1, 1, BLUE)
  check.call('many_draws', near.call(px.call(many.get_pixel(50, 10)), [0, 255, 0, 254]) && px.call(many.get_pixel(99, 14)) == [0, 0, 255, 255],
             "#{px.call(many.get_pixel(50, 10)).inspect} #{px.call(many.get_pixel(99, 14)).inspect}")
  # A fill with an empty rectangle draws nothing (an empty scissor box must not disable clipping)
  many.fill_rect(0, 0, 0, 15, RED)
  check.call('empty_fill', px.call(many.get_pixel(5, 5))[0] < 10, px.call(many.get_pixel(5, 5)).inspect)
  # 20 bitmaps become render targets in one frame (GPU queue entries per frame are limited)
  targets = Array.new(20) do
    bm = Bitmap.new(32, 32)
    bm.blt(0, 0, gsrc, gsrc.rect, 128)
    bm
  end
  check.call('many_targets', targets.all? { |bm| bm.get_pixel(0, 0).green > 100 }, targets.map { |bm| bm.get_pixel(0, 0).green.round }.uniq.inspect)
  targets.each(&:dispose)

  # Window contents at the window's position (simpleColor.vert translation)
  win = Window.new
  win.x = 320; win.y = 240; win.width = 160; win.height = 120
  win.contents = Bitmap.new(128, 88)
  win.contents.fill_rect(win.contents.rect, GREEN)
  Graphics.update
  snap = Graphics.snap_to_bitmap
  sx = snap.width / 640.0
  inside = px.call(snap.get_pixel((400 * sx).to_i, (300 * sx).to_i))
  outside = px.call(snap.get_pixel((100 * sx).to_i, (100 * sx).to_i))
  check.call('window_position', inside[0..2] == [0, 255, 0] && outside[0..2] != [0, 255, 0],
             "#{snap.width}x#{snap.height} inside #{inside.inspect} outside #{outside.inspect}")
  win.dispose

  # Effects on the screen (TEV presets), read back with snap_to_bitmap: 100x100 sprites/planes in
  # a grid, sampled in their centers
  solid = lambda do |color|
    bm = Bitmap.new(100, 100)
    bm.fill_rect(bm.rect, color)
    bm
  end
  objs = []
  place = lambda do |obj, col, row|
    obj.x = 10 + col * 120 if obj.respond_to?(:x=)
    obj.y = 10 + row * 120 if obj.respond_to?(:y=)
    objs << obj
    obj
  end
  sp = ->(color, col, row) { s1 = Sprite.new; s1.bitmap = solid.call(color); place.call(s1, col, row) }
  sp.call(RED, 0, 0).tone = Tone.new(-255, 100, 0)                 # tone: (0, 100, 0)
  sp.call(GREEN, 1, 0).tone = Tone.new(0, 0, 0, 255)               # gray: luma of green 150
  sp.call(RED, 2, 0).color = Color.new(0, 0, 255, 128)             # color: (127, 0, 128)
  bush = sp.call(WHITE, 3, 0)                                      # bush: lower 30 rows at 128
  bush.bush_depth = 30
  sp.call(GREEN, 4, 0).tone = Tone.new(-100, 0, 0, 255)            # gray + negative tone: (50, 150, 150)
  inv = sp.call(RED, 0, 1)                                         # invert (mkxp-z): (0, 255, 255)
  inv.invert = true
  tc = sp.call(Color.new(51, 51, 51), 1, 1)                        # tone + color, GLSL clamps once:
  tc.tone = Tone.new(-255, -255, -255)                             # mix(0.2 - 1, 1, 0.5) -> 26
  tc.color = Color.new(255, 255, 255, 128)
  it = sp.call(RED, 2, 1)                                          # invert after tone: (0, 155, 255)
  it.tone = Tone.new(0, 100, 0)
  it.invert = true
  vp = Viewport.new(130, 250, 100, 100)                            # viewport tone: (0, 0, 255)
  vp.tone = Tone.new(-255, -255, 0)
  vs = Sprite.new(vp); vs.bitmap = solid.call(WHITE); objs << vs << vp
  vg = Viewport.new(250, 250, 100, 100)                            # viewport gray: 150
  vg.tone = Tone.new(0, 0, 0, 255)
  vgs = Sprite.new(vg); vgs.bitmap = solid.call(GREEN); objs << vgs << vg
  pv = Viewport.new(370, 250, 100, 100)                            # plane tone: (255, 0, 255)
  pl = Plane.new(pv); pl.bitmap = solid.call(BLUE); pl.tone = Tone.new(255, 0, 0); objs << pl << pv
  Graphics.update
  fx = Graphics.snap_to_bitmap
  at = ->(x, y) { px.call(fx.get_pixel(x, y))[0..2] }
  check.call('sprite_tone', near.call(at.call(60, 60), [0, 100, 0]), at.call(60, 60).inspect)
  check.call('sprite_gray', near.call(at.call(180, 60), [150, 150, 150]), at.call(180, 60).inspect)
  check.call('sprite_color', near.call(at.call(300, 60), [127, 0, 128]), at.call(300, 60).inspect)
  check.call('sprite_bush', near.call(at.call(420, 30), [255, 255, 255]) && near.call(at.call(420, 100), [128, 128, 128]),
             "#{at.call(420, 30).inspect} #{at.call(420, 100).inspect}")
  check.call('sprite_gray_tone', near.call(at.call(540, 60), [50, 150, 150]), at.call(540, 60).inspect)
  check.call('sprite_invert', near.call(at.call(60, 180), [0, 255, 255]), at.call(60, 180).inspect)
  check.call('sprite_tone_color', near.call(at.call(180, 180), [26, 26, 26]), at.call(180, 180).inspect)
  check.call('sprite_invert_tone', near.call(at.call(300, 180), [0, 155, 255]), at.call(300, 180).inspect)
  check.call('viewport_tone', near.call(at.call(180, 300), [0, 0, 255]), at.call(180, 300).inspect)
  check.call('viewport_gray', near.call(at.call(300, 300), [150, 150, 150]), at.call(300, 300).inspect)
  check.call('plane_tone', near.call(at.call(420, 300), [255, 0, 255]), at.call(420, 300).inspect)
  fx.dispose
  objs.each(&:dispose)

  # Transitions: fade from black to a blue screen, plain and with a transition map
  # (trans-map.png from make-transmap.rb, a vertical gradient); the new scene must be on screen
  # afterwards
  [nil, 'trans-map.png'].each_with_index do |file, i|
    Graphics.freeze
    blue = Sprite.new; blue.bitmap = solid.call(BLUE); blue.zoom_x = 6.4; blue.zoom_y = 4.8
    file ? Graphics.transition(20, file, 40) : Graphics.transition(20)
    shot2 = Graphics.snap_to_bitmap
    check.call("transition_#{i}", near.call(px.call(shot2.get_pixel(320, 240))[0..2], [0, 0, 255]), px.call(shot2.get_pixel(320, 240)).inspect)
    shot2.dispose
    blue.dispose
    Graphics.update
  end

  # Screen scene: 640x480 game screen, quadrants as one 64x64 bitmap scaled 5x
  bg = Sprite.new
  bg.bitmap = Bitmap.new(640, 480)
  bg.bitmap.fill_rect(bg.bitmap.rect, Color.new(96, 96, 96))
  q = Bitmap.new(64, 64)
  q.fill_rect(0, 0, 32, 32, RED); q.fill_rect(32, 0, 32, 32, GREEN)
  q.fill_rect(0, 32, 32, 32, BLUE); q.fill_rect(32, 32, 32, 32, WHITE)
  s = Sprite.new
  s.bitmap = q; s.x = 160; s.y = 80; s.zoom_x = 5.0; s.zoom_y = 5.0; s.z = 10
  60.times { Graphics.update }
  shot = Graphics.snap_to_bitmap
  scene = [[600, 440], [200, 100], [400, 150], [200, 300], [400, 300]].map { |x, y| px.call(shot.get_pixel(x, y))[0..2] }
  check.call('screen_scene', scene == [[96, 96, 96], [255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 255]], scene.inspect)
  shot.dispose
rescue Exception => e
  check.call('exception', false, "#{e.class}: #{e.message} @ #{e.backtrace&.first}")
end
ok = results.none? { |l| l.include?('FAILED') }
line = "RMXP3DS_TEST render #{ok ? 'PASS' : 'FAIL'} checks=#{results.size}\n"
Dir.mkdir('sdmc:/rmxp3ds/test') unless Dir.exist?('sdmc:/rmxp3ds/test')
File.write('sdmc:/rmxp3ds/test/render-results.txt', line + results.join("\n") + "\n")
File.write('sdmc:/rmxp3ds/test/render.txt', line)
$stderr.puts line, results
240.times { Graphics.update } # keep the scene on screen for the screenshot
[s, bg].compact.each { |o| o.bitmap&.dispose; o.dispose } # leave a clean screen (tools/hw3 runs more checks after this one)
