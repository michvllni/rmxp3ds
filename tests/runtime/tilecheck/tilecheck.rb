# SPDX-License-Identifier: GPL-3.0-or-later
# Tile check for the 3DS runtime (mkxp-z-3ds, run as customScript): drives the native map
# renderer RMXP3DSTileRenderer (docs/DECISIONS.md D17) with synthetic images from
# make-assets.rb (Graphics/Tilesets/tileset.png 256x1100, Graphics/Autotiles/autotile.png,
# single.png and autotile192.png) and synthetic maps, then reads the screen back with
# Graphics.snap_to_bitmap: tileset tiles (also beyond 1024 px in the source, and a partial last
# row), block, single-tile and Essentials' 192 px autotiles and their frames, layer order,
# priorities, bridges and reflective tiles against sprites by z, a later map overwriting with
# blank tiles, scrolling, empty cells outside the map, tone, a tileset disposed while in use,
# and use after dispose. Result in sdmc:/rmxp3ds/test/tile.txt (details tile-results.txt).
results = []
Dir.mkdir('sdmc:/rmxp3ds/test') unless Dir.exist?('sdmc:/rmxp3ds/test')
log_path = 'sdmc:/rmxp3ds/test/tile-results.txt'
# Every line is appended at once (file closed after each), so a crash or freeze keeps what ran.
log_line = lambda do |text|
  File.open(log_path, 'a') { |f| f.puts(text) }
  $stderr.puts(text)
end
File.write(log_path, "RMXP3DS_TEST tile RUNNING\n")
check = lambda do |name, ok, info = nil|
  results << format('check %s %s%s', name, ok ? 'ok' : 'FAILED', info ? " (#{info})" : '')
  log_line.call(results.last)
end
rgb = ->(c) { [c.red.round, c.green.round, c.blue.round] }
near = ->(a, b, tol = 6) { a.zip(b).all? { |x, y| (x - y).abs <= tol } }
tile_color = ->(n) { [(n % 16) * 16 + 8, (n / 16) * 12 + 8, 200] }
TS = 384 # first tileset id; with one single-tile extra autotile, id 384 is that autotile
sprites = []

begin
  vp = Viewport.new(0, 0, 640, 480)
  r = RMXP3DSTileRenderer.new(vp)
  ts = Bitmap.new('Graphics/Tilesets/tileset')
  check.call('tileset_mega', ts.mega?, "#{ts.width}x#{ts.height}")
  h_ts = r.add_source(ts, 0, 0.25)
  at_bmp = Bitmap.new('Graphics/Autotiles/autotile')
  h_at = r.add_source(at_bmp, 1, 0.25)
  at_bmp.dispose # small images are copied
  single_bmp = Bitmap.new('Graphics/Autotiles/single')
  h_single = r.add_source(single_bmp, 1, 0.25)
  single_bmp.dispose
  at192_bmp = Bitmap.new('Graphics/Autotiles/autotile192')
  h_at192 = r.add_source(at192_bmp, 1, 0.25)
  at192_bmp.dispose
  check.call('frame_counts', r.frame_count(h_at) == 2 && r.frame_count(h_single) == 2,
             "#{r.frame_count(h_at)}, #{r.frame_count(h_single)}")

  # map 18 x 20 (narrower than the 21-column screen grid): layer 0 tileset tiles n = 1 + ...
  data = Table.new(18, 20, 3)
  18.times { |x| 20.times { |y| data[x, y, 0] = TS + 1 + ((x + y * 8) % 271) } }
  data[6, 1, 0] = TS + 270   # tile row 33: source y 1056, beyond 1024 px
  data[2, 3, 0] = 48         # block autotile 0, sub-tile 0
  data[3, 3, 0] = TS         # single-tile extra autotile
  data[5, 5, 1] = TS + 50    # priority 1 over a sprite at z 224
  data[7, 5, 1] = TS + 50    # priority 1 under a sprite at z 226
  data[8, 5, 0] = TS + 60    # reflective (z -100), under a sprite at z -50
  data[10, 5, 1] = TS + 100  # priority 0 on layer 1 over layer 0
  data[4, 3, 0] = 96 + 1     # 192 px autotile (slot 1), sub-tile 1 stored whole
  data[12, 5, 1] = TS + 70   # priority 1 and bridge: z 0 while a bridge is active
  data[13, 6, 0] = TS + 272  # partial last tileset row (12 px of 32)
  flags = Table.new(TS + 280)
  flags[TS + 50] = 1         # priority 1
  flags[TS + 60] = 8         # shows reflections
  flags[TS + 70] = 1 | 16    # priority 1, bridge
  map = [data, flags, 0, 0, h_ts, [h_at, h_at192], [], [h_single]]
  # a second, later map: 4 x 4 x 1 layer, all blank, at tile offset (-10, -1): it covers screen
  # cells (10..13, 1..4) and overwrites the first map there with nothing
  blank = [Table.new(4, 4, 1), nil, -10, -1, h_ts, [], [], []]

  sprite_at = lambda do |x, y, z, color|
    s = Sprite.new(vp)
    s.bitmap = Bitmap.new(32, 32)
    s.bitmap.fill_rect(0, 0, 32, 32, Color.new(*color))
    s.x = x
    s.y = y
    s.z = z
    sprites << s
  end
  sprite_at.call(5 * 32, 5 * 32, 224, [255, 0, 0])   # below the priority tile (z 225)
  sprite_at.call(7 * 32, 5 * 32, 226, [255, 0, 0])   # above it
  sprite_at.call(8 * 32, 5 * 32, -50, [0, 0, 255])   # above the reflective tile (z -100)
  sprite_at.call(9 * 32, 5 * 32, -50, [0, 255, 0])   # below the ground tile (z 0)
  sprite_at.call(12 * 32, 5 * 32, 10, [255, 0, 255]) # below the bridge tile (z 225), above it on a bridge (z 0)

  snap = lambda do |&blk|
    2.times { Graphics.update }
    shot = Graphics.snap_to_bitmap
    px = ->(x, y) { rgb.call(shot.get_pixel(x * shot.width / 640, y * shot.height / 480)) }
    blk.call(px)
    shot.dispose
  end
  n_at = ->(x, y) { 1 + ((x + y * 8) % 271) }

  r.update([map, blank], 0, 0, false, 0.0)
  snap.call do |px|
    c = px.call(11 * 32 + 16, 2 * 32 + 16)
    check.call('later_map_blank_overwrites', near.call(c, [0, 0, 0]), c.inspect)
    c = px.call(4 * 32 + 16, 3 * 32 + 16)
    check.call('autotile_192_whole_subtile', near.call(c, [10, 20, 30]), c.inspect)
    c = px.call(12 * 32 + 16, 5 * 32 + 16)
    check.call('bridge_off_priority', near.call(c, tile_color.call(70)), c.inspect)
    c = px.call(1 * 32 + 16, 1 * 32 + 16)
    check.call('tileset_tile', near.call(c, tile_color.call(n_at.call(1, 1))), c.inspect)
    c = px.call(6 * 32 + 16, 1 * 32 + 16)
    check.call('tileset_beyond_1024', near.call(c, tile_color.call(270)), c.inspect)
    # sub-tile 0 pieces: top left = piece 26, bottom right = piece 33 (autotileRects)
    tl = px.call(2 * 32 + 4, 3 * 32 + 4)
    br = px.call(2 * 32 + 28, 3 * 32 + 28)
    check.call('autotile_frame0', near.call(tl, [40, 130, 50]) && near.call(br, [40, 165, 50]),
               "#{tl.inspect} #{br.inspect}")
    c = px.call(3 * 32 + 16, 3 * 32 + 16)
    check.call('single_autotile_frame0', near.call(c, [250, 250, 0]), c.inspect)
    c = px.call(5 * 32 + 16, 5 * 32 + 16)
    check.call('priority_over_sprite', near.call(c, tile_color.call(50)), c.inspect)
    c = px.call(7 * 32 + 16, 5 * 32 + 16)
    check.call('sprite_over_priority', near.call(c, [255, 0, 0]), c.inspect)
    c = px.call(8 * 32 + 16, 5 * 32 + 16)
    check.call('sprite_over_reflection', near.call(c, [0, 0, 255]), c.inspect)
    c = px.call(9 * 32 + 16, 5 * 32 + 16)
    check.call('ground_over_sprite', near.call(c, tile_color.call(n_at.call(9, 5))), c.inspect)
    c = px.call(10 * 32 + 16, 5 * 32 + 16)
    check.call('layer1_over_layer0', near.call(c, tile_color.call(100)), c.inspect)
    c = px.call(13 * 32 + 16, 6 * 32 + 4)
    check.call('partial_last_row', near.call(c, tile_color.call(272)), c.inspect)
    c = px.call(19 * 32 + 16, 1 * 32 + 16)
    check.call('outside_map_empty', near.call(c, [0, 0, 0]), c.inspect)
  end

  r.update([map], 0, 0, true, 0.0)
  snap.call do |px|
    c = px.call(12 * 32 + 16, 5 * 32 + 16)
    check.call('bridge_on_ground', near.call(c, [255, 0, 255]), c.inspect)
  end

  # 0.3 s later: frame 1 of both autotiles
  r.update([map], 0, 0, false, 0.3)
  snap.call do |px|
    tl = px.call(2 * 32 + 4, 3 * 32 + 4)
    check.call('autotile_frame1', near.call(tl, [140, 130, 50]), tl.inspect)
    c = px.call(3 * 32 + 16, 3 * 32 + 16)
    check.call('single_autotile_frame1', near.call(c, [0, 250, 250]), c.inspect)
  end

  # scrolled 8 px to the right and 16 px down: cell (1,1) moves 8 px left and 16 px up
  r.update([map], 8, 16, false, 0.0)
  snap.call do |px|
    c = px.call(1 * 32 + 16 - 8, 1 * 32 + 16 - 16)
    check.call('scroll', near.call(c, tile_color.call(n_at.call(1, 1))), c.inspect)
  end

  # no seams while scrolling by sub-tile amounts: at 0.625 scale tile edges fall between screen
  # pixels; a row through opaque tiles (y = 1 * 32 + 16, columns 11..15) must never show
  # the black background or neighbouring atlas tiles' alpha (seen on the console as black lines)
  seams = []
  [3, 5, 7, 11, 13, 19, 21, 27, 29].each do |sx|
    r.update([map], sx, 0, false, 0.0)
    snap.call do |px|
      (11 * 32...16 * 32).each do |x|
        c = px.call(x, 1 * 32 + 16)
        seams << "#{sx}:#{x}" if c.sum < 60
      end
    end
  end
  check.call('scroll_no_seams', seams.empty?, seams.first(60).join(' '))

  # tone on the tiles only (sprites keep their colors)
  r.tone = Tone.new(-255, 0, 0)
  r.update([map], 0, 0, false, 0.0)
  snap.call do |px|
    c = px.call(1 * 32 + 16, 1 * 32 + 16)
    want = tile_color.call(n_at.call(1, 1))
    check.call('tone', c[0] <= 12 && near.call(c[1..2], want[1..2]), c.inspect)
    c = px.call(7 * 32 + 16, 5 * 32 + 16)
    check.call('tone_tiles_only', near.call(c, [255, 0, 0]), c.inspect)
  end
  r.tone = Tone.new(0, 0, 0)
  r.update([map], 0, 0, false, 0.0)

  # the tileset bitmap is read in place: disposing it while in use makes tiles not yet in the
  # atlas draw blank (no read of freed memory); tiles already uploaded stay
  ts.dispose
  data[14, 8, 0] = TS + 200 # never drawn before
  r.update([map], 0, 0, false, 0.0)
  snap.call do |px|
    c = px.call(14 * 32 + 16, 8 * 32 + 16)
    check.call('disposed_source_blank', near.call(c, [0, 0, 0]), c.inspect)
    c = px.call(1 * 32 + 16, 1 * 32 + 16)
    check.call('disposed_source_uploaded_tiles', near.call(c, tile_color.call(n_at.call(1, 1))), c.inspect)
  end
  r.remove_source(h_ts)
  r.dispose
  check.call('dispose', r.disposed? && r.frame_count(h_at) == 0)
  after = begin
    r.add_source(Bitmap.new(32, 32), 1, 0.25)
    'accepted'
  rescue RGSSError, StandardError => e
    e.class.name
  end
  check.call('use_after_dispose_raises', after != 'accepted', after)
rescue Exception => e # rubocop:disable Lint/RescueException (MKXPError is not a StandardError)
  check.call('exception', false, "#{e.class}: #{e.message} @ #{e.backtrace&.first}")
end
ok = results.none? { |l| l.include?('FAILED') }
line = "RMXP3DS_TEST tile #{ok ? 'PASS' : 'FAIL'} checks=#{results.size}\n"
log_line.call(line.chomp)
File.write('sdmc:/rmxp3ds/test/tile.txt', line)
240.times { Graphics.update }
