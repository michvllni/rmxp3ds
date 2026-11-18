# SPDX-License-Identifier: GPL-3.0-or-later
# Engine check for the 3DS runtime (mkxp-z-3ds, run as customScript; no rendering checks yet):
# RGSS classes, Zlib, fonts, Input, Graphics frame counting, platform. Writes the self-reporting
# result to sdmc:/rmxp3ds/test/mkxp.txt (details in mkxp-results.txt).
results = []
check = lambda do |name, ok, info = nil|
  results << format('check %s %s%s', name, ok ? 'ok' : 'FAILED', info ? " (#{info})" : '')
end
begin
  zl = begin; require 'zlib'; 'loaded'; rescue Exception => e; "#{e.class}: #{e.message}"; end
  check.call('zlib', defined?(Zlib) && Zlib::Inflate.inflate(Zlib::Deflate.deflate('abc')) == 'abc', "#{zl}; features=#{$LOADED_FEATURES.grep(/zlib/).inspect}")
  t = Table.new(4, 3, 2); t[3, 2, 1] = 77
  check.call('table', t[3, 2, 1] == 77 && t.xsize == 4)
  c = Color.new(10, 20, 30, 40); tone = Tone.new(-10, 0, 10, 50); r = Rect.new(1, 2, 3, 4)
  check.call('color_tone_rect', c.red == 10 && tone.gray == 50 && r.width == 3)
  check.call('marshal_table', Marshal.load(Marshal.dump(t))[3, 2, 1] == 77)
  b = Bitmap.new(64, 32)
  check.call('bitmap', b.width == 64 && b.height == 32 && b.rect.width == 64)
  b.font.size = 22
  sz = b.text_size('rmxp3ds')
  check.call('text_size', sz.width > 40 && sz.height > 10, "#{sz.width}x#{sz.height}")
  vp = Viewport.new(0, 0, 320, 240); vp.z = 5
  sp = Sprite.new(vp); sp.bitmap = b; sp.x = 10; sp.zoom_x = 2.0; sp.opacity = 128
  check.call('sprite', sp.x == 10 && sp.zoom_x == 2.0 && sp.opacity == 128 && sp.viewport == vp)
  w = Window.new; w.x = 4; w.width = 100; w.height = 64; w.contents = Bitmap.new(68, 32)
  check.call('window', w.width == 100 && w.contents.width == 68)
  tm = Tilemap.new(vp); tm.tileset = Bitmap.new(256, 4096); tm.map_data = Table.new(20, 15, 3)
  check.call('tilemap_big_tileset', tm.tileset.height == 4096)
  tm.dispose
  Graphics.play_movie('missing.ogv') rescue check.call('play_movie', false, $!.message)
  check.call('controller_name', Input::Controller.name == 'Nintendo 3DS', Input::Controller.name.inspect)
  dd = System.data_directory
  check.call('data_directory', dd.end_with?('/'), dd)
  f0 = Graphics.frame_count
  t0 = Time.now
  30.times { Graphics.update; Input.update }
  dt = Time.now - t0
  check.call('graphics_update', Graphics.frame_count - f0 == 30, format('30 frames in %.2f s, rate %d', dt, Graphics.frame_rate))
  check.call('input', !Input.press?(Input::C) && Input.dir4 == 0)
  check.call('rgss1', defined?(RPG::Sprite) && RUBY_VERSION == '3.1.3' && System.platform == 'Nintendo 3DS', "#{RUBY_VERSION} #{System::VERSION rescue '?'}")
  [sp, w, vp, b].each(&:dispose)
  check.call('dispose', b.disposed? && sp.disposed?)
rescue Exception => e
  check.call('exception', false, "#{e.class}: #{e.message} @ #{e.backtrace&.first}")
end
ok = results.none? { |l| l.include?('FAILED') }
line = "RMXP3DS_TEST mkxp #{ok ? 'PASS' : 'FAIL'} checks=#{results.size}\n"
Dir.mkdir('sdmc:/rmxp3ds/test') unless Dir.exist?('sdmc:/rmxp3ds/test')
File.write('sdmc:/rmxp3ds/test/mkxp-results.txt', line + results.join("\n") + "\n")
File.write('sdmc:/rmxp3ds/test/mkxp.txt', line)
$stderr.puts line, results
