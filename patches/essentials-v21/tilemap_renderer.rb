# SPDX-License-Identifier: GPL-3.0-or-later
# rmxp3ds patch for Pokémon Essentials v21 (docs/DECISIONS.md D17): draws maps with the runtime's
# native RMXP3DSTileRenderer instead of Essentials' Ruby TilemapRenderer (one Sprite per screen
# cell and layer). Loaded as an mkxp-z preload script, before the game's scripts; it changes no
# game file. When the game defines TilemapRenderer, its `new` is redirected to
# RMXP3DS::EssentialsTilemap, which keeps the interface the game uses (add_/remove_tileset,
# add_/remove_autotile, add_/remove_extra_autotiles, refresh, update, tone, color, dispose).
# TilemapRenderer's constants and helpers (ZOOM_X/Y, TilesetWrapper, ...) stay the game's own.
# Without RMXP3DSTileRenderer (other runtimes) nothing is changed.
module RMXP3DS
  class EssentialsTilemap
    AUTOTILE_SECONDS = 5 / 20.0 # Essentials' default autotile frame duration

    attr_reader :viewport
    attr_accessor :ox, :oy, :visible # no effect, as in Essentials

    def initialize(viewport = nil)
      @viewport = viewport
      @native = RMXP3DSTileRenderer.new(viewport)
      @t0 = System.uptime
      @sources = {} # [kind, name] => [handle, references]
      @flags = {}   # tileset id => Table of per-tile-id flags
      @ox = @oy = 0
      @visible = true
      @disposed = false
    end

    def tone = @native.tone
    def tone=(value)
      @native.tone = value
    end

    def color = @native.color
    def color=(value)
      @native.color = value
    end

    def add_tileset(name) = add_source(:tileset, name)
    def remove_tileset(name) = remove_source(:tileset, name)
    def add_autotile(name) = add_source(:autotile, name)
    def remove_autotile(name) = remove_source(:autotile, name)

    def add_extra_autotiles(tileset_id)
      extras(tileset_id).flatten.each { |name| add_autotile(name) }
    end

    def remove_extra_autotiles(tileset_id)
      extras(tileset_id).flatten.each { |name| remove_autotile(name) }
    end

    def refresh; end # the native renderer rebuilds every frame

    def update
      return if @disposed || @native.disposed? # Graphics.reset disposes the native side

      release_unused

      maps = $map_factory ? $map_factory.maps : [$game_map]
      inputs = maps.compact.map { |map| map_input(map) }
      cur = $game_map
      px = (cur.display_x / 4.0).round % 32
      py = (cur.display_y / 4.0).round % 32
      bridge = $PokemonGlobal && $PokemonGlobal.bridge.to_i > 0
      @native.update(inputs, px, py, bridge, System.uptime - @t0)
    end

    def dispose
      return if @disposed

      @native.dispose if !@native.disposed?
      @sources.each_value { |entry| entry[2]&.dispose }
      @sources.clear
      @disposed = true
    end

    def disposed? = @disposed

    private

    def extras(tileset_id)
      table = defined?(TilemapRenderer::EXTRA_AUTOTILES) ? TilemapRenderer::EXTRA_AUTOTILES : {}
      entry = table[tileset_id] || [[], []]
      [Array(entry[0]), Array(entry[1])]
    end

    # Copies a tileset or autotile image into the native atlas (reference-counted per file name).
    def add_source(kind, name)
      return if name.nil? || name.empty?

      key = [kind, name]
      if (entry = @sources[key])
        entry[1] += 1 # also revives an entry waiting for release_unused (map transfers)
        return
      end
      bitmap, own = load_bitmap(kind, name)
      seconds = AUTOTILE_SECONDS
      seconds = Regexp.last_match(1).to_i / 20.0 if kind == :autotile && name[/\[\s*(\d+)\s*\]\s*$/]
      handle = @native.add_source(bitmap, kind == :tileset ? 0 : 1, seconds)
      keep = own && bitmap.mega? # read in place by the native side: alive until released
      bitmap.dispose if own && !keep
      @sources[key] = [handle, 1, keep ? bitmap : nil]
    end

    # Returns [bitmap, owned]. Tall images (above 1024 px) become CPU "mega" bitmaps that the
    # native renderer reads in place, so they are loaded uncached and owned here. Other autotiles
    # come from RPG::Cache (copied by the native side, left to the cache). A missing tileset
    # gives a blank bitmap, like Essentials' loader.
    def load_bitmap(kind, name)
      if kind == :autotile
        bitmap = pbGetAutotile(name)
        return [bitmap, false] if !bitmap.mega?

        return [Bitmap.new("Graphics/Autotiles/" + name), true]
      end
      [Bitmap.new("Graphics/Tilesets/" + name), true]
    rescue StandardError, MKXPError
      [Bitmap.new(32, 32), true]
    end

    def remove_source(kind, name)
      entry = @sources[[kind, name]]
      return if !entry

      entry[1] -= 1 if entry[1] > 0
    end

    # Releases sources nobody uses any more, once per frame: a map transfer removes and re-adds
    # the same tileset, which then stays in the atlas instead of being decoded again.
    def release_unused
      @sources.delete_if do |_key, entry|
        next false if entry[1] > 0

        @native.remove_source(entry[0])
        entry[2]&.dispose
        true
      end
    end

    def handle(kind, name)
      return -1 if name.nil? || name.empty?

      entry = @sources[[kind, name]]
      entry ? entry[0] : -1
    end

    # Per tile id: priority (bits 0-2), shows reflections (bit 3), bridge (bit 4).
    def flags_for(map)
      @flags[map.tileset_id] ||= begin
        prio = map.priorities
        tags = map.terrain_tags
        n = [prio ? prio.xsize : 0, tags ? tags.xsize : 0].max
        t = Table.new(n)
        n.times do |id|
          p = (prio && prio[id]) || 0
          tag = GameData::TerrainTag.try_get((tags && tags[id]) || 0)
          p = 0 if p < 0 || p > 7 # out-of-range priorities count as 0
          t[id] = p | (tag&.shows_reflections ? 8 : 0) | (tag&.bridge ? 16 : 0)
        end
        t
      end
    end

    def map_input(map)
      dx = (map.display_x / 4.0).round
      dy = (map.display_y / 4.0).round
      large, single = extras(map.tileset_id)
      [map.data, flags_for(map), dx.div(32), dy.div(32), handle(:tileset, map.tileset_name),
       Array.new(7) { |i| handle(:autotile, map.autotile_names[i]) },
       large.map { |n| handle(:autotile, n) }, single.map { |n| handle(:autotile, n) }]
    end
  end

  # Redirects TilemapRenderer.new once the game has defined the class.
  module TilemapRendererNew
    def new(*args) = RMXP3DS::EssentialsTilemap.new(*args)
  end

  TILEMAP_TRACE = TracePoint.new(:end) do |tp|
    next unless tp.self.is_a?(Class) && tp.self.name == 'TilemapRenderer'

    tp.self.singleton_class.prepend(TilemapRendererNew)
    TILEMAP_TRACE.disable
  end
end

RMXP3DS::TILEMAP_TRACE.enable if defined?(RMXP3DSTileRenderer)
