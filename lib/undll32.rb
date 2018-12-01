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

    def _unpack x
      case x
      when Integer
        buffer[(@_i += x) - x, x].sub(/\0+$/, '')
      when Symbol
        n = { C: 1, S: 2, L: 4, Q: 8 }[x]
        if n.nil?
          raise ArgumentError, "expected CSLQ, got #{x}"
        end
        buffer[(@_i += n) - n, n].unpack1("#{x}")
      when Array
        x.map { |e| _unpack e }
      when Hash
        Hash[x.map { |k, v| [k, _unpack(v)] }]
      else
        raise ArgumentError, "expected hash, array, sym, int, got #{struct}"
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
        raise ArgumentError, "expected hash, array, sym, int, got #{struct}"
      end
    ensure
      $@.shift if $@
    end
  end

  # Undll32.run 'user32', 'MessageBox', 0, 'hello', 'world', 0
  def self.run(dll, func, *args)
    types = args.map { |e| Integer === e ? 'L' : 'p' }
    input = args.map { |e| Buffer === e ? e.buffer : e }
    Win32API.new(dll, func, types, 'i').call(*input)
  end

  def self.parse xs
    case x = xs.shift
    when ':' then Buffer.new xs.shift.to_i
    when '[' then Buffer.new xs.shift.chars.map(&:to_sym)
    when '{'
      x = Hash[xs.each_slice(4).map { |k, _, v, _| [k.to_sym, v.to_sym] }]
      Buffer.new x
    else
      raise ArgumentError, "expected : [ {, got #{x}"
    end
  end

  def self.exe(argv=ARGV)
    return help if ARGV.include? '-h' or ARGV.include? '--help'
    dllfunc, *args = argv
    return help if dllfunc.nil?
    dll, func = dllfunc.split(',')
    return help if func.nil?
    args.map! { |e|
      e = e.dup
      if e.start_with?('+')
        e.slice!(0)
        next e if e.start_with?('+')
        parse e.scan(/\w+|./)
      else
        n = Integer(e) rescue nil
        next n if n
        e
      end
    }
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
      undll32 user32,GetCursorPos +{x:L,y:L}
      undll32 user32,GetCursorPos +:8 # will be converted to string

    EXPLAIN
      0   => (Integer) 0
      str => 'str'
      +0  => '0'
      ++0 => '+0'
      +[CSLQ]    => Buffer.new([:C, :S, :L, :Q])
      +{x:L,y:L} => Buffer.new({:x => :L, :y => :L})
      +:256      => Buffer.new(256)

    USAGE
  end
end
