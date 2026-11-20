# SPDX-License-Identifier: GPL-3.0-or-later
# Engine check for the 3DS runtime (mkxp-z-3ds, run as customScript; no rendering checks yet):
# RGSS classes, Zlib, fonts, Input, Graphics frame counting, platform. Writes the self-reporting
# result to sdmc:/rmxp3ds/test/mkxp.txt (details in mkxp-results.txt).
results = []
Dir.mkdir('sdmc:/rmxp3ds/test') unless Dir.exist?('sdmc:/rmxp3ds/test')
log_path = 'sdmc:/rmxp3ds/test/mkxp-results.txt'
# Every line is appended at once (file closed after each), so a crash or freeze keeps what ran.
log_line = lambda do |text|
  File.open(log_path, 'a') { |f| f.puts(text) }
  $stderr.puts(text)
end
File.write(log_path, "RMXP3DS_TEST mkxp RUNNING\n")
check = lambda do |name, ok, info = nil|
  results << format('check %s %s%s', name, ok ? 'ok' : 'FAILED', info ? " (#{info})" : '')
  log_line.call(results.last)
end
begin
  zl = begin; require 'zlib'; 'loaded'; rescue Exception => e; "#{e.class}: #{e.message}"; end
  check.call('zlib', defined?(Zlib) && Zlib::Inflate.inflate(Zlib::Deflate.deflate('abc')) == 'abc', "#{zl}; features=#{$LOADED_FEATURES.grep(/zlib/).inspect}")
  # encoding table linked (enc/encinit.a before libruby-static.a): constants and a transcoder
  enc_ok = begin
    Encoding.const_defined?(:UTF_8) && Encoding.name_list.size > 50 &&
      "caf\u00e9".encode('ISO-8859-1').bytesize == 4
  rescue Exception => e
    "#{e.class}: #{e.message}"
  end
  check.call('encodings', enc_ok == true, "#{Encoding.name_list.size} names; #{enc_ok}")
  # Ruby's compiler with devkitARM's one-byte enums (fork Ruby patch 0006): `next` in a `while`
  # loop compiles to putnil, ADJUST(redo label), jump. Without the patch, an ADJUST whose label
  # pointer has the low byte 60 (= BIN(jump)) was taken for a jump and crashed the peephole
  # optimizer. 120 loops put their redo labels on many arena addresses, and the 60 compiles shift
  # the arena; a broken build crashes here with high likelihood.
  src = +"def rb3ds_compile_check(a)\n  out = []\n"
  120.times do |k|
    src << "  i = 0\n  while i < a.size\n    i += 1\n    next if a[i - 1] == #{k % 7}\n    out << #{k}\n  end\n"
  end
  src << "  out\nend\n"
  pads = []
  60.times do |n|
    pads << ('p' * (n * 13 % 97 + 1))
    RubyVM::InstructionSequence.compile(src)
  end
  eval(src)
  cres = rb3ds_compile_check([0, 1, 2])
  # values 0..2 each skip the loops with k % 7 == value: 120 * 3 - 52 = 308 entries
  check.call('compile_next_loops', cres.size == 308 && cres.first(4) == [0, 0, 1, 1], "#{cres.size} values")
  # textures of bitmaps read with get_pixel are released on dispose (fork bitmap.cpp hook):
  # 24 x 640x480 (2 MB of linear memory each on the 3DS) would exhaust the 32 MB linear heap
  red = Color.new(255, 0, 0)
  24.times do
    lb = Bitmap.new(640, 480)
    lb.fill_rect(0, 0, 640, 480, red)
    lb.get_pixel(1, 1)
    lb.dispose
  end
  lb = Bitmap.new(640, 480)
  lb.fill_rect(0, 0, 640, 480, red)
  lc = lb.get_pixel(320, 240)
  lb.dispose
  check.call('get_pixel_no_texture_leak', lc.red.round == 255 && lc.alpha.round == 255,
             "#{lc.red.round},#{lc.green.round},#{lc.blue.round},#{lc.alpha.round}")
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
  # textures are at most 1024 px (PICA200): mkxp-z's RGSS Tilemap takes tilesets up to about
  # 1300 px tall (atlas lanes) and refuses taller ones; the converter splits those (PLAN 3.2)
  tm = Tilemap.new(vp); tm.tileset = Bitmap.new(256, 1024); tm.map_data = Table.new(20, 15, 3)
  check.call('tilemap_tileset_1024', tm.tileset.height == 1024)
  tall = begin
    tm.tileset = Bitmap.new(256, 4096)
    'accepted'
  rescue MKXPError, StandardError => e # MKXPError is not a StandardError
    e.message
  end
  check.call('tilemap_tall_tileset_refused', tall.include?('tileset atlas'), tall)
  tm.dispose
  # movies are left out on the 3DS: play_movie logs and returns, even for a missing file
  movie = begin
    Graphics.play_movie('missing.ogv')
    nil
  rescue StandardError => e
    e.message
  end
  check.call('play_movie', movie.nil?, movie || 'returned')
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
log_line.call(line.chomp)
File.write('sdmc:/rmxp3ds/test/mkxp.txt', line)
