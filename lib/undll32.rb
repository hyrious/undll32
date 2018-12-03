require "undll32/version"
require 'win32api'

##
# Undll32
# replacement of Windows' rundll32.exe
module Undll32

  ##
  # represents a string/struct
  # Buffer.new({ :x => :L, :y => 4 })
  # Buffer.new([ :L, 4 ])
  # Buffer.new(:L)
  # Buffer.new(4)
  # buffer.buffer => "\0\0\0\0"
  # buffer.unpack => 0
  class Buffer
    attr_accessor :struct

    def initialize struct
      case struct
      when Hash, Array, Symbol, Integer
        @struct = struct
      else
        raise ArgumentError, "expected hash, array, sym, int, got #{struct}"
      end
    end

    def buffer
      @buffer ||= _buffer(@struct)
    end

    def unpack
      @_i = 0
      _unpack @struct
    end

    def load v
      @_i = 0
      _load @struct, v
      unpack
    end

    def _load x, v
      case x
      when Integer
        return @_i += x if v.nil?
        unless String === v
          raise ArgumentError, "expected str, got #{v}"
        end
        x = [x, v.length].min
        buffer[(@_i += x) - x, x] = v[0, x]
      when Symbol
        n = { C: 1, S: 2, L: 4, Q: 8 }[x]
        if n.nil?
          raise ArgumentError, "expected CSLQ, got #{x}"
        end
        return @_i += n if v.nil?
        unless Integer === v
          raise ArgumentError, "expected int, got #{v}"
        end
        buffer[(@_i += n) - n, n] = [v].pack("#{x}")
      when Array
        return x.each { |a| _load a, nil } if v.nil?
        unless Array === v and v.size == x.size
          raise ArgumentError, "expected array[#{x.size}], got #{v}"
        end
        x.zip(v) { |a, b| _load a, b }
      when Hash
        return x.each { |k, y| _load y, nil } if v.nil?
        unless Hash === v
          raise ArgumentError, "expected hash, got #{v}"
        end
        x.each { |k, y| _load y, v[k] }
      else
        raise ArgumentError, "expected hash, array, sym, int, got #{x}"
      end
    ensure
      $@.shift if $@
    end

    def _unpack x
      case x
      when Integer
        buffer[(@_i += x) - x, x].sub(/\0+$/, '')
      when Symbol
        n = { C: 1, S: 2, L: 4, Q: 8 }[x]
        buffer[(@_i += n) - n, n].unpack1("#{x}")
      when Array
        x.map { |e| _unpack e }
      when Hash
        Hash[x.map { |k, v| [k, _unpack(v)] }]
      else
        raise ArgumentError, "expected hash, array, sym, int, got #{x}"
      end
    ensure
      $@.shift if $@
    end

    def _buffer x
      case x
      when Integer
        [].pack("x#{x}")
      when Symbol
        n = { C: 1, S: 2, L: 4, Q: 8 }[x]
        if n.nil?
          raise ArgumentError, "expected CSLQ, got #{x}"
        end
        [].pack("x#{n}")
      when Array
        x.map { |e| _buffer e }.join
      when Hash
        _buffer x.values
      else
        raise ArgumentError, "expected hash, array, sym, int, got #{x}"
      end
    ensure
      $@.shift if $@
    end

    def self.from_array code
      unless code =~ /^\[[CSLQ]+\]$/
        raise ArgumentError, "expected [CSLQ], got #{code}"
      end
      return new(code[1..-2].chars.map(&:to_sym))
    end

    def self.from_size code
      m = code.match(/^\:(?<size>[^=]+)=?(?<value>.+)?$/)
      if m.nil?
        raise ArgumentError, "expected <number> or CSLQ, got #{code}"
      end
      if m[:size] =~ /^[CSLQ]+$/
        s = m[:size].chars.map(&:to_sym)
        if s.size == 1
          return new(s[0]).tap { |b| b.load(m[:value].to_i) if m[:value] }
        else
          b = new(s)
          b.load(m[:value].split(':').map(&:to_i)) if m[:value]
          return b
        end
      end
      if (n = m[:size].to_i)
        return new(n).tap { |b| b.load(m[:value]) if m[:value] }
      end
      raise ArgumentError, "expected <number> or CSLQ, got #{code}"
    end

    def self.next_placeholder
      @_placeholder_counter ||= 0
      "__#{@_placeholder_counter += 1}__"
    end

    def self.from_struct code
      default = {}
      # code := '{' [name] [:type] [=value] [,...] '}'
      env, keys, key = [], [], ''
      seq = code.scan /\w+|\:[[:digit:]]+|\:[CSLQ:]+|=[^,\}]+|./
      ret = while (token = seq.shift)
        case token[0]
        when '{'
          keys.push(key.to_sym) unless key.empty?
          env.push({})
          key = ''
        when '}'
          env[-1][key.to_sym] = :L unless key.empty?
          x = env.pop
          break x if env.empty?
          env[-1][keys.pop] = x
          key = ''
        when ':'
          token << seq.shift if seq.first&.start_with?('=')
          b = from_size(token)
          key = next_placeholder if key.empty?
          env[-1][key.to_sym] = b.struct
          d = default
          keys.each { |k| d[k] ||= {}; d = d[k] }
          d[key.to_sym] = b.unpack
          key = ''
        when '='
          e = token[1..-1]
          e = Integer(e) rescue nil
          type = Integer === e ? :L : (e.length + 1)
          env[-1][key.to_sym] = type
          d = default
          keys.each { |k| d[k] ||= {}; d = d[k] }
          if Integer === type
            e = "\"#{e}\"".undump rescue e.undump
          end
          d[key.to_sym] = e
          key = ''
        when ','
          next if key.empty?
          env[-1][key.to_sym] = :L
          key = ''
        else
          key << token
        end
      end
      if ret.nil?
        raise ArgumentError, 'expected }, got end-of-input'
      end
      new(ret).tap { |b| b.load(default) }
    end

    def self.from code
      return from_array(code) if code.start_with?('[')
      return from_size(code) if code.start_with?(':')
      code = "{#{code}}" unless code.start_with?('{')
      return from_struct(code)
    end
  end

  # Undll32.run 'user32', 'MessageBox', 0, 'hello', 'world', 0
  # Undll32.run 'user32', 'GetCursorPos', Buffer.new({:x => :L, :y => :L})
  # Undll32.run 'user32', 'GetCursorPos', Buffer.from('x,y')
  def self.run(dll, func, *args)
    types = args.map { |e| Integer === e ? 'L' : 'p' }
    input = args.map { |e| Buffer === e ? e.buffer : e }
    Win32API.new(dll, func, types, 'i').call(*input)
  end

  def self.exe(argv=ARGV)
    return help if ARGV.include? '-h' or ARGV.include? '--help'
    dllfunc, *args = argv
    return help if dllfunc.nil?
    dll, func = dllfunc.split(',')
    return help if func.nil?
    args.map! do |e|
      e = e.dup
      if e.start_with?('+')
        e.slice!(0)
        next e if e.start_with?('+')
        Buffer.from(e)
      else
        n = Integer(e) rescue nil
        next n if n
        e
      end
    end
    ret = run(dll, func, *args)
    args.each { |e| pp e.unpack if Buffer === e }
    ret
  end

  def self.help
    puts <<-USAGE

    undll32 dll,func [...args]

    EXAMPLE
      undll32 user32,MessageBox 0 hello world 0
      undll32 user32,GetCursorPos +[LL]
      undll32 user32,GetCursorPos +x,y
      undll32 user32,GetCursorPos +:8 # will be converted to string

    ARGUMENTS
      0   => (Integer) 0
      str => 'str'
      +0  => '0'
      ++0 => '+0'
      +[CSLQ]    => Buffer.new([:C, :S, :L, :Q])
      +{x:L,y:L} => Buffer.new({:x => :L, :y => :L})
      +:256      => Buffer.new(256)

    VERSION
      #{VERSION}

    USAGE
  end
end
