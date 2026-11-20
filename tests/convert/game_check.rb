# SPDX-License-Identifier: GPL-3.0-or-later
# Script section "Main" of the synthetic game from tests/fixtures/make-rmxp-game.rb: run in the
# 3DS runtime from a package written by convert/rmxp3ds-convert, it checks what the converter
# put into the package and reports to sdmc:/rmxp3ds/test/convert.txt (details in
# convert-results.txt).
results = []
Dir.mkdir('sdmc:/rmxp3ds/test') unless Dir.exist?('sdmc:/rmxp3ds/test')
log_path = 'sdmc:/rmxp3ds/test/convert-results.txt'
File.write(log_path, "RMXP3DS_TEST convert RUNNING\n")
check = lambda do |name, ok, info = nil|
  results << format('check %s %s%s', name, ok ? 'ok' : 'FAILED', info ? " (#{info})" : '')
  File.open(log_path, 'a') { |f| f.puts(results.last) }
  $stderr.puts(results.last)
end
begin
  check.call('started_from_games_dir', Dir.pwd.end_with?('rmxp3ds/games/rmxp3ds-convert-test'), Dir.pwd)
  check.call('patch_set_preloaded', $rmxp3ds_convert_patch == :loaded)
  conf = File.read('mkxp.json')
  check.call('mkxp_json_written', conf.include?('rmxp3ds-convert') && conf.include?('"framebufferScalingFactor": 0.500000'))
  check.call('pc_files_left_out', !File.exist?('Game.exe') && !File.exist?('RGSS102E.dll'))
  check.call('report_present', File.exist?('rmxp3ds/convert-report.txt'))
  bmp = Bitmap.new('Graphics/Pictures/rmxp3ds-test')
  c = bmp.get_pixel(10, 10)
  check.call('picture', bmp.width == 64 && bmp.height == 32 && c.red == 200 && c.green == 40, "#{bmp.width}x#{bmp.height} #{c.red},#{c.green}")
  map = load_data('Data/Map001.rxdata')
  check.call('map_data', map.width == 20 && map.height == 15, "#{map.width}x#{map.height}")
  tilesets = load_data('Data/Tilesets.rxdata')
  check.call('tileset_data', tilesets[1].tileset_name == 'rmxp3ds-tiles')
  sprite = Sprite.new
  sprite.bitmap = bmp
  30.times { Graphics.update }
  check.call('frames', true)
rescue Exception => e
  check.call('exception', false, "#{e.class}: #{e.message} @ #{e.backtrace&.first}")
end
ok = results.none? { |l| l.include?('FAILED') }
line = "RMXP3DS_TEST convert #{ok ? 'PASS' : 'FAIL'} checks=#{results.size}\n"
File.open(log_path, 'a') { |f| f.puts(line) }
$stderr.puts(line)
File.write('sdmc:/rmxp3ds/test/convert.txt', line)
120.times { Graphics.update }
