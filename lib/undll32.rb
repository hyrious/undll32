require "undll32/version"

module Undll32
  def self.run(dll, func, *args)
    require 'win32api'
    types = args.map { |e| Integer === e ? 'L' : 'p' }
    Win32API.new(dll, func, types, 'i').call(*args)
  end
  def self.exe(argv=ARGV)
    require 'win32api'
    dll, func = argv.shift.split(',')
    types, params = argv.map {|e|
      type, value = ?p, e.dup
      if e[0] == ?*
        value.slice!(0)
      else
        begin
          value = Integer(e)
          type = ?L
        rescue ArgumentError
        end
      end
      [type, value]
    }.transpose
    Win32API.new(dll, func, types, 'i').call(*params)
  end
end
