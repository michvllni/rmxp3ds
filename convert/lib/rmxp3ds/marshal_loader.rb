# SPDX-License-Identifier: GPL-3.0-or-later
# Loads RPG Maker XP data files (.rxdata, Marshal) on the PC without RGSS. Classes the data
# names (RPG::Map, RPG::Tileset, a game's own classes ...) are defined on first use as empty
# classes that keep their instance variables; classes with a binary _dump (Table, Color, Tone,
# unknown user types) keep their raw bytes, and Table also decodes its RGSS layout. Nothing from
# the data is executed: only empty classes are created, at top level as Marshal looks them up,
# so the converter runs in its own process.
module RMXP3DS
  module Data
    # Base for auto-created classes: instance variables are readable with #[] (:name or '@name').
    class Plain
      def [](name)
        name = name.to_s
        instance_variable_get(name.start_with?('@') ? name : "@#{name}")
      end
    end

    # Auto-created class with a binary _dump: the bytes as they were.
    class Raw
      attr_reader :raw

      def self._load(str)
        obj = allocate
        obj.instance_variable_set(:@raw, str)
        obj
      end
    end

    # RGSS Table (_dump: int32 dim, xsize, ysize, zsize, count, then count int16 values).
    class Table < Raw
      attr_reader :xsize, :ysize, :zsize

      def self._load(str)
        obj = super
        _dim, x, y, z, n = str.unpack('l<5')
        obj.instance_variable_set(:@xsize, x)
        obj.instance_variable_set(:@ysize, y)
        obj.instance_variable_set(:@zsize, z)
        obj.instance_variable_set(:@data, str.byteslice(20, n * 2).unpack('s<*'))
        obj
      end

      def [](x, y = 0, z = 0)
        @data[x + y * @xsize + z * @xsize * @ysize]
      end
    end

    # Upper bound of classes defined while loading one file (guards against a loop on an error
    # message that define_missing misreads).
    MAX_NEW_CLASSES = 500

    module_function

    # Marshal.load of a file with auto-created classes. Raises on a damaged file.
    def load_file(path)
      load(File.binread(path))
    end

    def load(bytes)
      MAX_NEW_CLASSES.times do
        return Marshal.load(bytes)
      rescue ArgumentError, TypeError => e
        raise unless define_missing(e.message)
      end
      raise ArgumentError, 'too many unknown classes in the data'
    end

    # Defines the class named in a Marshal error: "undefined class/module RPG::Map" (a plain
    # class) or "class RPG::X needs to have method `_load'" (a raw-bytes class; Table decodes).
    # Returns false for any other message (the caller re-raises).
    def define_missing(message)
      if (m = message.match(%r{undefined class/module ([\w:]+)}))
        define_path(m[1], Plain)
      elsif (m = message.match(/class ([\w:]+) needs to have method `_load'/))
        define_path(m[1], m[1] == 'Table' ? Table : Raw, replace: true)
      else
        return false
      end
      true
    end

    # Defines A::B::C at top level: missing namespaces as plain classes (Marshal accepts a class
    # as namespace), C with the given superclass. An existing C is kept, unless `replace` is set
    # and C is one of our plain classes (it then lacked _load).
    def define_path(path, superclass, replace: false)
      parts = path.split('::')
      scope = parts[0..-2].reduce(Object) do |s, name|
        s.const_defined?(name, false) ? s.const_get(name, false) : s.const_set(name, Class.new(Plain))
      end
      name = parts.last
      if scope.const_defined?(name, false)
        existing = scope.const_get(name, false)
        return existing unless replace && existing.is_a?(Class) && existing <= Plain
        scope.send(:remove_const, name)
      end
      scope.const_set(name, Class.new(superclass))
    end
  end
end
