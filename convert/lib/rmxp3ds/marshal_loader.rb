# SPDX-License-Identifier: GPL-3.0-or-later
# Reads RPG Maker XP data files (.rxdata, Ruby Marshal format 4.8) on the PC without RGSS and
# without Ruby's Marshal.load: a pure reader that never instantiates or calls a Ruby class named
# in the data, so a crafted file cannot run code through existing classes (Marshal gadgets).
# Objects become Plain (class name + instance variables), user-dumped objects (_dump: Table,
# Color, Tone ...) become Raw with their bytes (Table also decodes its RGSS layout), strings keep
# their bytes (UTF-8 if the data says so, else binary).
module RMXP3DS
  module Data
    class FormatError < StandardError; end

    # An object from the data: its class name and instance variables (readable with #[]).
    class Plain
      attr_reader :class_name, :ivars

      def initialize(class_name)
        @class_name = class_name
        @ivars = {}
      end

      # Instance variable by name (:tileset_name, '@tileset_name').
      def [](name)
        name = name.to_s
        @ivars[name.start_with?('@') ? name : "@#{name}"]
      end
    end

    # A user-dumped object (_dump / marshal_load data): class name and bytes or data.
    class Raw
      attr_reader :class_name, :raw

      def initialize(class_name, raw)
        @class_name = class_name
        @raw = raw
      end
    end

    # RGSS Table (_dump: int32 dim, xsize, ysize, zsize, count, then count int16 values).
    class Table < Raw
      attr_reader :xsize, :ysize, :zsize

      def initialize(class_name, raw)
        super
        raise FormatError, 'Table data too short' if raw.bytesize < 20
        _dim, @xsize, @ysize, @zsize, n = raw.unpack('l<5')
        @data = raw.byteslice(20, n * 2).to_s.unpack('s<*')
      end

      def [](x, y = 0, z = 0)
        @data[x + y * @xsize + z * @xsize * @ysize]
      end
    end

    # Struct from the data ('S'): class name and members.
    class StructValue < Plain; end

    module_function

    def load_file(path)
      load(File.binread(path))
    end

    def load(bytes)
      Reader.new(bytes).read
    end

    # Marshal 4.8 reader (format: ruby/doc/marshal.rdoc; object link order as marshal.c
    # r_object). Depth-limited against nesting bombs (RMXP data nests fewer than 15 levels).
    class Reader
      MAX_DEPTH = 200

      def initialize(bytes)
        @s = bytes.b
        @pos = 0
        @symbols = []
        @objects = []
        @depth = 0
      end

      def read
        major, minor = byte, byte
        raise FormatError, "not Marshal 4.8 data (#{major}.#{minor})" unless major == 4 && minor <= 8
        value
      rescue SystemStackError
        raise FormatError, 'data nested too deep'
      end

      private

      def byte
        b = @s.getbyte(@pos) or raise FormatError, 'data too short'
        @pos += 1
        b
      end

      def bytes(n)
        raise FormatError, 'data too short' if n.negative? || @pos + n > @s.bytesize
        str = @s.byteslice(@pos, n)
        @pos += n
        str
      end

      # Marshal's packed integer.
      def int
        c = byte
        c -= 256 if c > 127
        return 0 if c.zero?
        return c - 5 if c > 4
        return c + 5 if c < -4
        if c.positive?
          (0...c).reduce(0) { |v, i| v | (byte << (8 * i)) }
        else
          n = -c
          v = (0...n).reduce(0) { |acc, i| acc | (byte << (8 * i)) }
          v - (1 << (8 * n))
        end
      end

      # A symbol in a name position; 'I' wraps a symbol with an encoding (Ruby 1.9+ non-ASCII
      # names): its ivars are read and dropped.
      def symbol
        case (t = byte.chr)
        when ':' then new_symbol
        when ';' then link(@symbols, 'symbol')
        when 'I'
          sym = symbol
          int.times do
            symbol
            value
          end
          sym
        else raise FormatError, "symbol expected, got #{t.inspect}"
        end
      end

      def link(table, what)
        idx = int
        raise FormatError, "bad #{what} link" if idx.negative? || idx >= table.size
        table[idx]
      end

      def new_symbol
        sym = bytes(int).force_encoding('UTF-8')
        sym = sym.b unless sym.valid_encoding?
        @symbols << sym
        sym
      end

      def register(obj)
        @objects << obj
        obj
      end

      def value
        @depth += 1
        raise FormatError, 'data nested too deep' if @depth > MAX_DEPTH
        read_value
      ensure
        @depth -= 1
      end

      def read_value
        type = byte.chr
        case type
        when '0' then nil
        when 'T' then true
        when 'F' then false
        when 'i' then int
        when ':' then new_symbol
        when ';' then link(@symbols, 'symbol')
        when '@' then link(@objects, 'object')
        when 'I' then with_ivars
        when '"' then register(bytes(int))
        when 'l'
          sign = byte.chr
          n = int * 2
          v = n.zero? ? 0 : bytes(n).reverse.unpack1('H*').to_i(16) # little-endian, linear time
          register(sign == '-' ? -v : v)
        when 'f'
          s = bytes(int)
          register(case s
                   when 'inf' then Float::INFINITY
                   when '-inf' then -Float::INFINITY
                   when 'nan' then Float::NAN
                   else s.to_f
                   end)
        when '[' then array
        when '{', '}' then hash(type == '}')
        when 'o' then object
        when 'u'
          name = symbol
          register(user(name, bytes(int)))
        when 'U'
          name = symbol
          obj = register(Raw.new(name, nil))
          obj.instance_variable_set(:@raw, value)
          obj
        when 'S' then struct
        when 'c', 'm', 'M' then register(bytes(int)) # class/module reference: its name only
        when '/'
          src = bytes(int)
          byte # options
          register(src)
        when 'e'
          symbol # extended module: ignored
          value
        when 'C'
          symbol # user subclass of String/Array/Hash: the base value
          value
        else
          raise FormatError, "unsupported Marshal type #{type.inspect} at byte #{@pos - 1}"
        end
      end

      # 'I': a value followed by instance variables; for strings, E/encoding set the encoding.
      # 'I' around 'u': marshal.c reads the dumped string's ivars before it registers the user
      # object, so the order of object links stays the same as Ruby's.
      def with_ivars
        return user_with_ivars if @s.getbyte(@pos) == 'u'.ord

        obj = value
        apply_ivars(obj)
        obj
      end

      def user_with_ivars
        @pos += 1
        name = symbol
        raw = bytes(int)
        apply_ivars(raw)
        register(user(name, raw))
      end

      def apply_ivars(obj)
        int.times do
          key = symbol
          val = value
          next unless obj.is_a?(String)
          if key == 'E'
            obj.force_encoding(val ? 'UTF-8' : 'US-ASCII')
          elsif key == 'encoding'
            obj.force_encoding(val.to_s) rescue obj.force_encoding('BINARY') # rubocop:disable Style/RescueModifier
          end
        end
      end

      def array
        arr = register([])
        int.times { arr << value }
        arr
      end

      def hash(with_default)
        h = register({})
        int.times do
          k = value
          h[k] = value
        end
        value if with_default # default value: ignored
        h
      end

      def object
        obj = register(Plain.new(symbol))
        int.times do
          key = symbol
          obj.ivars[key] = value
        end
        obj
      end

      def struct
        obj = register(StructValue.new(symbol))
        int.times do
          key = symbol
          obj.ivars["@#{key}"] = value
        end
        obj
      end

      def user(name, raw)
        name == 'Table' ? Table.new(name, raw) : Raw.new(name, raw)
      end
    end
  end
end
