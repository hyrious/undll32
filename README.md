# Undll32

Replacement of Windows' `rundll32.exe`.

Notice: it uses `require 'win32api'`, which may not work on your Linux or MacOS systems.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'undll32'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install undll32

## Usage

- `undll32`: `undll32 User32,MessageBox 0 hello world 0`
- `ruby -r`: `ruby -rundll32 -e Undll32.exe -- User32,MessageBox 0 hello world 0`
- Program: `Undll32.run('User32', 'MessageBox', 0, 'hello', 'world', 0)`

### Another Programming Usage (x86 only)

It may be easier (and shorter) to work with win32api with such script:

```ruby
# [def] void assert!(bool expression, string message = nil)
#
# [def] Either<Buffer, Array> buf(string template = nil)
#    buf('LL') #=> #<Buffer LL>
#    buf       #=> [ 0, 0 ] /* by unpacking previous #<Buffer> */
#
# [def] int api(string dll, string func)
#    api('user32', 'MessageBox').call(0, 'Hello', 0, 16)
#    api('user32', 'GetCursorPos').call(buf('LL')); buf #=> [ 12, 34 ]
#
# [def] Dll dll(string dll)
#    dll('user32').GetCursorPos(buf('LL'))
#
# [const] Kernel32, User32
#
# [def] string ptr2str(int ptr)
#
# [def] string String#to_ws()
#       string String#from_ws()
#       int String#to_ptr()

def assert! bool, message=nil
  raise ArgumentError, message || "assertion fail" unless bool
ensure
  $@.shift if $@
end

# api.call(nil, true, false, buf('LL'))
class NilClass; def to_int() 0 end end
class TrueClass; def to_int() 1 end end
class FalseClass; def to_int() 0 end end

class Buffer
  def self.buf(template=nil)
    if template.nil?
      @buf && @buf.unpack
    else
      @buf = Buffer.new template
    end
  end
  TemplateSizes = Hash[{
    %w[C c       A a x] => 1,
    %w[S s n v]         => 2,
    %w[L l N V F f e g] => 4,
    %w[Q q     D d E G] => 8,
  }.map { |k, v| k.map { |l| [l, v] } }.flatten(1)]
  def self.parse(template)
    template = template.gsub(/(\w)(\d+)/) { |m| m[0] * Integer(m[1..-1]) }
    [].pack("x#{template.chars.map { |c| TemplateSizes[c] }.inject(:+)}")
  end
  def initialize(template)
    assert!(String === template)
    @template = template
    @buffer = Buffer.parse template
  end
  attr_reader :buffer
  def unpack(template = @template)
    @buffer.unpack template
  end
  def load(*data)
    @template.scan(/\w(?:\d*)/).zip(data).reduce(0) { |s, (t, d)|
      n = TemplateSizes[t[0]] * (t.length > 1 ? Integer(t[1..-1]) : 1)
      @buffer[s, n] = [*d].pack(t) unless t.nil? || d.nil?
      s + n
    }; self
  end
  def inspect
    "#<Buffer #{unpack.inspect}>"
  end
  def to_str
    @buffer
  end
  def to_int
    [@buffer].pack('p').unpack('L')[0]
  end
end
def buf(*args) Buffer.buf(*args) end

# api('user32', 'GetCursorPos').call(buf('LL')); p buf #=> [12, 34]
class Api
  def initialize dll, fun
    assert!(String === dll && String === fun)
    @dll, @fun = dll, fun
  end
  attr_reader :dll, :fun
  alias func fun
  def call *args
    import = args.map { |e| Integer === e ? 'L' : 'p' }
    @instance ||= Win32API.new(@dll, @fun, import, 'L')
    @instance.call(*args)
  end
  alias [] call
  def inspect
    "#<Api #@dll.#@fun>"
  end
end
def api(*args) Api.new(*args) end

def ptr2str pointer
  assert!(Integer === pointer)
  len = api('kernel32', 'lstrlen').call pointer
  return '' if len.zero?
  str = [].pack("x#{len}")
  api('kernel32', 'RtlMoveMemory').call str, pointer, len
  str
end

class String
  def to_ws()   unpack('U*').pack('S*') end
  def from_ws() unpack('S*').pack('U*') end
  def to_ptr()  [self].pack('p').unpack('L')[0] end
end

class Dll
  def initialize dll
    @dll = dll
    @api = {}
  end
  def method_missing fun, *args
    @api[fun] ||= Api.new(@dll, fun.to_s)
    @api[fun].call *args
  end
  def inspect
    "#<Dll #@dll>"
  end
  def to_a
    @api.values
  end
end
def dll(name) Dll.new(name) end

Kernel32 = dll('kernel32')
User32 = dll('user32')
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/hyrious/undll32.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
