# SPDX-License-Identifier: GPL-3.0-or-later
# Minimal RGSS1 data classes for Marshal round trips (field names per the public RPG Maker XP
# reference), a Table with RGSS's binary _dump/_load layout, and a deterministic synthetic map.
# Shared by tests/fixtures/make-rxdata.rb (host) and bench.rb (3DS), so both agree on layout.

class Table
  attr_reader :xsize, :ysize, :zsize

  def initialize(x, y = 1, z = 1)
    @dim = 1 + (y > 1 ? 1 : 0) + (z > 1 ? 1 : 0)
    @xsize, @ysize, @zsize = x, y, z
    @data = Array.new(x * y * z, 0)
  end

  def [](x, y = 0, z = 0)
    @data[x + y * @xsize + z * @xsize * @ysize]
  end

  def []=(*args)
    v = args.pop
    x, y, z = args[0], args[1] || 0, args[2] || 0
    @data[x + y * @xsize + z * @xsize * @ysize] = v
  end

  # RGSS layout: int32 dim, xsize, ysize, zsize, count, then count int16 values.
  def _dump(_depth = 0)
    [@dim, @xsize, @ysize, @zsize, @data.size].pack('l<5') + @data.pack('s<*')
  end

  def self._load(str)
    dim, x, y, z, n = str.unpack('l<5')
    t = new(x, y, z)
    t.instance_variable_set(:@dim, dim)
    t.instance_variable_set(:@data, str.byteslice(20, n * 2).unpack('s<*'))
    t
  end

  def data_sum
    @data.sum
  end
end

module RPG
  class Map
    attr_accessor :tileset_id, :width, :height, :autoplay_bgm, :bgm, :autoplay_bgs, :bgs,
                  :encounter_list, :encounter_step, :data, :events
  end

  class Event
    attr_accessor :id, :name, :x, :y, :pages
    class Page
      attr_accessor :condition, :graphic, :move_type, :move_speed, :move_frequency, :move_route,
                    :walk_anime, :step_anime, :direction_fix, :through, :always_on_top, :trigger, :list
    end
  end

  class EventCommand
    attr_accessor :code, :indent, :parameters
    def initialize(code = 0, indent = 0, parameters = [])
      @code, @indent, @parameters = code, indent, parameters
    end
  end
end

module RGSSStubs
  module_function

  # Deterministic linear congruential generator (same result on every Ruby/platform).
  def lcg(seed)
    s = seed
    -> { s = (s * 1_103_515_245 + 12_345) & 0x7fffffff }
  end

  def synthetic_map(width, height, events, seed)
    rnd = lcg(seed)
    m = RPG::Map.new
    m.tileset_id = 1
    m.width = width
    m.height = height
    m.autoplay_bgm = false
    m.encounter_list = []
    m.encounter_step = 30
    m.data = Table.new(width, height, 3)
    height.times { |y| width.times { |x| 3.times { |z| m.data[x, y, z] = rnd.call % 400 } } }
    m.events = {}
    (1..events).each do |id|
      e = RPG::Event.new
      e.id = id
      e.name = format('EV%03d', id)
      e.x = rnd.call % width
      e.y = rnd.call % height
      e.pages = Array.new(1 + rnd.call % 3) do
        p = RPG::Event::Page.new
        p.trigger = rnd.call % 3
        p.move_type = 0
        p.walk_anime = true
        p.list = Array.new(5 + rnd.call % 20) do |i|
          RPG::EventCommand.new(101 + rnd.call % 300, i % 3, [format('Text %d-%d', id, i), rnd.call % 100])
        end
        p
      end
      m.events[id] = e
    end
    m
  end

  # Order-independent checksum over the loaded structure (proves a full, correct load).
  def digest(map)
    sum = map.data.data_sum + map.width * 7 + map.height * 13
    map.events.each_value do |e|
      sum += e.id * 31 + e.x + e.y * 3 + e.name.bytes.sum
      e.pages.each do |p|
        sum += p.trigger
        p.list.each { |c| sum += c.code + c.indent + c.parameters[0].bytesize + c.parameters[1] }
      end
    end
    sum & 0xffffffff
  end
end
