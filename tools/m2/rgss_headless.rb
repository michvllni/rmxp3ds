# SPDX-License-Identifier: GPL-3.0-or-later
# Headless RGSS1/mkxp-z API for running game scripts without graphics, input or audio
# (benchmarks, tests). Data classes are real (Marshal formats as RGSS); everything visual is a
# quiet stand-in that keeps attributes and returns harmless values.

# Generic stand-in: stores any attribute, answers queries with nil. respond_to?/defined? stay
# truthful (no respond_to_missing?): scripts test them before aliasing or defining methods.
class HeadlessObject
  def initialize(*args)
    @args = args
  end

  def method_missing(name, *args, &block)
    n = name.to_s
    if n.end_with?('=')
      instance_variable_set("@#{n.chomp('=')}", args[0])
    elsif n.end_with?('?')
      false
    elsif instance_variable_defined?("@#{n}")
      instance_variable_get("@#{n}")
    end
  end

  def dispose; @disposed = true; end
  def disposed? = !!@disposed
end

class Color
  attr_accessor :red, :green, :blue, :alpha
  def initialize(r = 0, g = 0, b = 0, a = 255) = set(r, g, b, a)
  def set(r, g = 0, b = 0, a = 255)
    return set(r.red, r.green, r.blue, r.alpha) if r.is_a?(Color)
    @red, @green, @blue, @alpha = r.to_f, g.to_f, b.to_f, a.to_f
    self
  end
  def ==(o) = o.is_a?(Color) && [red, green, blue, alpha] == [o.red, o.green, o.blue, o.alpha]
  def _dump(_d = 0) = [@red, @green, @blue, @alpha].pack('E4')
  def self._load(s) = new(*s.unpack('E4'))
end

class Tone
  attr_accessor :red, :green, :blue, :gray
  def initialize(r = 0, g = 0, b = 0, gr = 0) = set(r, g, b, gr)
  def set(r, g = 0, b = 0, gr = 0)
    return set(r.red, r.green, r.blue, r.gray) if r.is_a?(Tone)
    @red, @green, @blue, @gray = r.to_f, g.to_f, b.to_f, gr.to_f
    self
  end
  def ==(o) = o.is_a?(Tone) && [red, green, blue, gray] == [o.red, o.green, o.blue, o.gray]
  def _dump(_d = 0) = [@red, @green, @blue, @gray].pack('E4')
  def self._load(s) = new(*s.unpack('E4'))
end

class Rect
  attr_accessor :x, :y, :width, :height
  def initialize(x = 0, y = 0, w = 0, h = 0) = set(x, y, w, h)
  def set(x, y = 0, w = 0, h = 0)
    return set(x.x, x.y, x.width, x.height) if x.is_a?(Rect)
    @x, @y, @width, @height = x, y, w, h
    self
  end
  def empty; @x = @y = @width = @height = 0; self; end
  def ==(o) = o.is_a?(Rect) && [x, y, width, height] == [o.x, o.y, o.width, o.height]
  def _dump(_d = 0) = [@x, @y, @width, @height].pack('l<4')
  def self._load(s) = new(*s.unpack('l<4'))
end

# RGSS Table: int16 values, Marshal layout: dim, xsize, ysize, zsize, count, data.
class Table
  attr_reader :xsize, :ysize, :zsize
  def initialize(x, y = 1, z = 1)
    @dim = 1 + (y > 1 ? 1 : 0) + (z > 1 ? 1 : 0)
    @xsize, @ysize, @zsize = x, y, z
    @data = Array.new(x * y * z, 0)
  end
  def [](x, y = 0, z = 0)
    return nil if x >= @xsize || y >= @ysize || z >= @zsize || x < 0 || y < 0 || z < 0
    @data[x + y * @xsize + z * @xsize * @ysize]
  end
  def []=(*a)
    v = a.pop
    x, y, z = a[0], a[1] || 0, a[2] || 0
    return if x >= @xsize || y >= @ysize || z >= @zsize
    @data[x + y * @xsize + z * @xsize * @ysize] = v
  end
  def resize(x, y = 1, z = 1)
    old = self.class.new(x, y, z)
    [x, @xsize].min.times { |i| [y, @ysize].min.times { |j| [z, @zsize].min.times { |k| old[i, j, k] = self[i, j, k] } } }
    @xsize, @ysize, @zsize, @data = x, y, z, old.instance_variable_get(:@data)
  end
  def _dump(_d = 0) = [@dim, @xsize, @ysize, @zsize, @data.size].pack('l<5') + @data.pack('s<*')
  def self._load(s)
    dim, x, y, z, n = s.unpack('l<5')
    t = new(x, y, z)
    t.instance_variable_set(:@dim, dim)
    t.instance_variable_set(:@data, s.byteslice(20, n * 2).unpack('s<*'))
    t
  end
end

class Font < HeadlessObject
  class << self
    attr_accessor :default_name, :default_size, :default_bold, :default_italic, :default_color,
                  :default_outline, :default_shadow, :default_out_color
    def exist?(_n) = true
  end
  self.default_name = 'Arial'
  self.default_size = 22
  attr_accessor :name, :size, :bold, :italic, :color, :outline, :shadow, :out_color
  def initialize(name = nil, size = nil)
    @name = name || Font.default_name
    @size = size || Font.default_size
    @color = Color.new(255, 255, 255, 255)
  end
end

class Bitmap < HeadlessObject
  # mkxp-z: largest texture size; 1024 on the 3DS (PICA200).
  def self.max_size = 1024
  attr_accessor :font
  def initialize(*args)
    super
    @w, @h = args[0].is_a?(Integer) ? [args[0], args[1]] : [32, 32]
    @font = Font.new
  end
  def width = @w
  def height = @h
  def rect = Rect.new(0, 0, @w, @h)
  def text_size(s) = Rect.new(0, 0, s.to_s.size * 8, 16)
  def get_pixel(*) = Color.new(0, 0, 0, 0)
  def clone = Bitmap.new(@w, @h)
  # Drawing is a no-op; defined explicitly because scripts alias these methods.
  %i[draw_text blt stretch_blt fill_rect gradient_fill_rect clear clear_rect set_pixel
     hue_change blur radial_blur].each { |m| define_method(m) { |*_a| self } }
end

class Viewport < HeadlessObject
  def initialize(*a)
    super
    @rect = a[0].is_a?(Rect) ? a[0] : Rect.new(*a)
    @color = Color.new(0, 0, 0, 0)
    @tone = Tone.new
    @visible = true
    @z = 0
    @ox = @oy = 0
  end
  attr_accessor :rect, :color, :tone, :visible, :z, :ox, :oy
  def update; end
  def flash(*); end
end

class Sprite < HeadlessObject
  attr_accessor :bitmap, :src_rect, :x, :y, :z, :ox, :oy, :zoom_x, :zoom_y, :angle, :mirror,
                :bush_depth, :opacity, :blend_type, :color, :tone, :visible, :viewport
  def initialize(viewport = nil)
    super
    @viewport = viewport
    @src_rect = Rect.new
    @x = @y = @z = @ox = @oy = @angle = @bush_depth = @blend_type = 0
    @zoom_x = @zoom_y = 1.0
    @opacity = 255
    @color = Color.new(0, 0, 0, 0)
    @tone = Tone.new
    @visible = true
    @mirror = false
  end
  def update; end
  def flash(*); end
  def width = @src_rect.width
  def height = @src_rect.height
end

class Plane < Sprite; end

class Window < HeadlessObject
  def initialize(viewport = nil)
    super
    @viewport = viewport
    @x = @y = @z = @ox = @oy = 0
    @width = @height = 32
    @opacity = @back_opacity = @contents_opacity = 255
    @visible = @active = true
    @cursor_rect = Rect.new
    @tone = Tone.new
  end
  def update; end
end

class Tilemap < HeadlessObject
  attr_accessor :tileset, :map_data, :flash_data, :priorities, :visible, :ox, :oy, :viewport
  def initialize(viewport = nil)
    super
    @viewport = viewport
    @autotiles = Array.new(7)
  end
  attr_reader :autotiles
  def update; end
end

module Graphics
  @frame_count = 0
  @frame_rate = (ENV['SIM_FPS'] || 30).to_i
  class << self
    attr_accessor :frame_count, :frame_rate, :brightness
    def update = @frame_count += 1
    def width = 512
    def height = 384
    def freeze; end
    def transition(*); end
    def frame_reset; end
    def wait(n) = n.times { update }
    def fadeout(*); end
    def fadein(*); end
    def resize_screen(*); end
    def delta = 1.0 / frame_rate
    def fullscreen = false
    def fullscreen=(_v); end
    def scale = 1.0
    def scale=(_v); end
    def center; end
    def snap_to_bitmap = Bitmap.new(width, height)
    def method_missing(*) = nil
  end
  self.brightness = 255
end

module Input
  %i[DOWN LEFT RIGHT UP A B C X Y Z L R SHIFT CTRL ALT F5 F6 F7 F8 F9 USE BACK ACTION SPECIAL
     AUX1 AUX2 JUMPUP JUMPDOWN MOUSELEFT MOUSERIGHT MOUSEMIDDLE].each_with_index { |s, i| const_set(s, 100 + i) }
  class << self
    def update; end
    def trigger?(*) = false
    # Keys held for benchmarks: Input.held = [Input::CTRL]
    attr_accessor :held
    def press?(k) = (@held || []).include?(k)
    def repeat?(*) = false
    def release?(*) = false
    # Scripted direction for benchmarks: Input.script = ->(frame) { 2/4/6/8 or 0 }
    attr_accessor :script
    def dir4 = @script ? @script.call(Graphics.frame_count) : 0
    def dir8 = dir4
    def mouse_x = 0
    def mouse_y = 0
    def mouse_in_window = false
    def time?(*) = 0
    def triggerex?(*) = false
    def repeatex?(*) = false
    def method_missing(*) = nil
  end
end

module Audio
  def self.method_missing(*) = nil
end

# mkxp-z additions
module System
  VERSION = '2.4.2/c9378cf'
  def self.platform = 'Headless'
  def self.data_directory = Dir.pwd
  def self.game_title = 'Headless'
  def self.user_language = 'en_US'
  def self.user_name = 'headless'
  # Simulated clock: game time advances 1/frame_rate per Graphics.update, so time-based game
  # logic behaves as at the target frame rate however fast or slow the machine runs.
  def self.uptime = 1000.0 + Graphics.frame_count.to_f / Graphics.frame_rate
  def self.power_state = { discharging: false, seconds: nil, percent: nil }
  def self.method_missing(*) = nil
end

module Kernel
  def load_data(path) = File.open(path, 'rb') { |f| Marshal.load(f) }
  def save_data(obj, path) = File.open(path, 'wb') { |f| Marshal.dump(obj, f) }
  def rgss_main = yield
  def rgss_stop = nil
  def msgbox(*a) = $stderr.puts("[msgbox] #{a.join(' ')}")
  def print(*a) = $stderr.puts("[print] #{a.join(' ')}")
end
