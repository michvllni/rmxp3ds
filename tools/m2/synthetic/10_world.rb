# SPDX-License-Identifier: GPL-3.0-or-later
# Synthetic game, section "World" (packed into Scripts.rxdata by tests/fixtures/make-game.rb).
# Not an RPG Maker game: just enough game-like Ruby to test the M2 pipeline without game content
# (scripts loaded from Scripts.rxdata, map data via load_data, a frame loop with a game clock).
# Integer-only (waits count frames, not float seconds) and driven by its own LCG, so every
# platform computes the same digest.

class SynthEvent
  attr_reader :id, :x, :y, :steps

  def initialize(id, x, y, commands)
    @id = id
    @x = x
    @y = y
    @commands = commands
    @steps = 0
    @wait_until = 0
  end

  DIRS = [[0, 1], [-1, 0], [1, 0], [0, -1]].freeze

  # One frame: moves one tile in a pseudo-random direction when passable; after a move, waits
  # 0-4 frames.
  def update(map, rnd)
    return if Graphics.frame_count < @wait_until

    dx, dy = DIRS[rnd.call % 4]
    nx = @x + dx
    ny = @y + dy
    return unless map.passable?(nx, ny)

    @x = nx
    @y = ny
    @steps += 1
    @wait_until = Graphics.frame_count + @commands % 5
  end
end

class SynthMap
  attr_reader :events

  def initialize(map_id)
    @map = load_data(format('Data/Map%03d.rxdata', map_id))
    @events = @map.events.keys.sort.map do |id|
      e = @map.events[id]
      SynthEvent.new(id, e.x, e.y, e.pages.sum { |p| p.list.size })
    end
  end

  def width = @map.width
  def height = @map.height

  # Tiles whose layer-0 id is a multiple of 7 block movement.
  def passable?(x, y)
    x >= 0 && y >= 0 && x < width && y < height && (@map.data[x, y, 0] % 7) != 0
  end

  def update(rnd)
    @events.each { |e| e.update(self, rnd) }
  end

  def digest
    @events.inject(0) { |sum, e| (sum * 31 + e.x * 1009 + e.y * 9176 + e.steps) & 0xffffffff }
  end
end
