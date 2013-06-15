# The most ugly test script I've ever written!
# Shame on me!

require 'pathname'
require 'profile' if ARGV.include? '-p'

MYDIR = File.dirname(__FILE__)
LIBDIR = Pathname.new(MYDIR).join('..', 'lib').cleanpath.to_s
$:.unshift MYDIR, LIBDIR
require 'coderay'

@size = ARGV.fetch(2, 100).to_i * 1000

lang = ARGV.fetch(0) do
  puts <<-HELP
Usage:
  ruby bench.rb (c|ruby) (null|text|tokens|count|statistic|yaml|html) [size in kB] [stream]

  SIZE defaults to 100 kB (= 100,000 bytes).
  SIZE = 0 means the whole input.

-p generates a profile (slow! use with SIZE = 1)
-o shows the output
stream enabled streaming mode

Sorry for the strange interface. I will improve it in the next release.
  HELP
  exit
end

format = ARGV.fetch(1, 'html').downcase

$stream = ARGV.include? 'stream'
$optimize = ARGV.include? 'opt'
$style = ARGV.include? 'style'

require 'benchmark'
require 'fileutils'

if format == 'comp'
  format = 'page'
  begin
    require 'syntax'
    require 'syntax/convertors/html.rb'
  rescue LoadError
    puts 'Syntax no found!! (Try % gem install syntax)'
  end
end

def here fn = nil
  return MYDIR unless fn
  File.join here, fn
end

n = ARGV.find { |a| a[/^N/] }
N = if n then n[/\d+/].to_i else 1 end
$filename = ARGV.include?('strange') ? 'strange' : 'example'

Benchmark.bm(20) do |bm|
N.times do

  data = nil
  File.open(here("#$filename." + lang), 'rb') { |f| data = f.read }
  raise 'Example file is empty.' if data.empty?
  unless @size.zero?
    data += data until data.size >= @size
    data = data[0, @size]
  end
  @size = data.size
  
  options = {
    :tab_width => 2,
    # :line_numbers => :inline,
    :css => $style ? :style : :class,
  }
  $hl = CodeRay.encoder(format, options)
  time = bm.report('CodeRay') do
    if $stream || true
      $o = $hl.encode(data, lang, options)
    else
      tokens = CodeRay.scan(data, lang)
      tokens.optimize! if $optimize
      $o = tokens.encode($hl)
    end
  end
  $file_created = here('test.' + $hl.file_extension)
  File.open($file_created, 'wb') do |f|
    # f.write $o
  end
  
  time_real = time.real
  
  puts "\t%7.2f KB/s (%d.%d KB)" % [((@size / 1000.0) / time_real), @size / 1000, @size % 1000]
  puts $o if ARGV.include? '-o'
  
end
end
puts "Files created: #$file_created"

STDIN.gets if ARGV.include? 'wait'

__END__
.ruby .normal {}
.ruby .comment { color: #005; font-style: italic; }
.ruby .keyword { color: #A00; font-weight: bold; }
.ruby .method { color: #077; }
.ruby .class { color: #074; }
.ruby .module { color: #050; }
.ruby .punct { color: #447; font-weight: bold; }
.ruby .symbol { color: #099; }
.ruby .string { color: #944; background: #FFE; }
.ruby .char { color: #F07; }
.ruby .ident { color: #004; }
.ruby .constant { color: #07F; }
.ruby .regex { color: #B66; background: #FEF; }
.ruby .number { color: #F99; }
.ruby .attribute { color: #7BB; }
.ruby .global { color: #7FB; }
.ruby .expr { color: #227; }
.ruby .escape { color: #277; }

.xml .normal {}
.xml .namespace { color: #B66; font-weight: bold; }
.xml .tag { color: #F88; }
.xml .comment { color: #005; font-style: italic; }
.xml .punct { color: #447; font-weight: bold; }
.xml .string { color: #944; }
.xml .number { color: #F99; }
.xml .attribute { color: #BB7; }

.yaml .normal {}
.yaml .document { font-weight: bold; color: #07F; }
.yaml .type { font-weight: bold; color: #05C; }
.yaml .key { color: #F88; }
.yaml .comment { color: #005; font-style: italic; }
.yaml .punct { color: #447; font-weight: bold; }
.yaml .string { color: #944; }
.yaml .number { color: #F99; }
.yaml .time { color: #F99; }
.yaml .date { color: #F99; }
.yaml .ref { color: #944; }
.yaml .anchor { color: #944; }
