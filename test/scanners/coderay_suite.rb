require 'benchmark'
require 'fileutils'

$mydir = File.dirname(__FILE__)
$:.unshift File.join($mydir, '..', '..', 'lib')

require 'coderay'

debug, $DEBUG = $DEBUG, false

require 'term/ansicolor' unless ENV['nocolor']

if defined? Term::ANSIColor
  class String
    include Term::ANSIColor
    def green_or_red result
      result ? green : red
    end
  end
else
  class String
    for meth in %w(green red blue cyan magenta yellow concealed white)
      class_eval <<-END
        def #{meth}
          self
        end
      END
    end
    def green_or_red result
      result ? upcase : downcase
    end
  end
end
$DEBUG = debug

unless defined? Term::ANSIColor
  puts 'You should gem install term-ansicolor.'
end

# from Ruby Facets (http://facets.rubyforge.org/)
class Array
  def shuffle!
    s = size
    each_index do |j|
      i = ::Kernel.rand(s-j)
      self[j], self[j+i] = at(j+i), at(j) unless i.zero?
    end
    self
  end unless [].respond_to? :shuffle!
end

# Wraps around an enumerable and prints the current element when iterated.
class ProgressPrinter
  
  attr_accessor :enum, :template
  attr_reader :progress
  
  def initialize enum, template = '(%p)'
    @enum = enum
    @template = template
    if ENV['showprogress']
      @progress = ''
    else
      @progress = nil
    end
  end
  
  def each
    for elem in @enum
      if @progress
        print "\b" * @progress.size
        @progress = @template % elem
        print @progress
      end
      yield elem
    end
  ensure
    print "\b" * progress.size if @progress
  end
  
  include Enumerable
  
end

module Enumerable
  def progress
    ProgressPrinter.new self
  end
end

module CodeRay
  
  if RUBY_VERSION >= '1.9'
    $:.unshift File.join($mydir, '..', 'lib')
  end
  require 'test/unit'
  
  class TestCase < Test::Unit::TestCase
    
    if ENV['deluxe']
      MAX_CODE_SIZE_TO_HIGHLIGHT = 500_000_000
      MAX_CODE_SIZE_TO_TEST = 500_000_000
      DEFAULT_MAX = 1024
    elsif ENV['fast']
      MAX_CODE_SIZE_TO_HIGHLIGHT = 5_000_000
      MAX_CODE_SIZE_TO_TEST = 1_000_000
      DEFAULT_MAX = 16
    else
      MAX_CODE_SIZE_TO_HIGHLIGHT = 5_000_000
      MAX_CODE_SIZE_TO_TEST = 5_000_000
      DEFAULT_MAX = 512
    end
    
    class << self
      def inherited child
        CodeRay::TestSuite << child.suite
      end
      
      # Calls its block with the working directory set to the examples
      # for this test case.
      def dir
        examples = File.join $mydir, lang.to_s
        Dir.chdir examples do
          yield
        end
      end
      
      def lang
        @lang ||= name[/[\w_]+$/].downcase
      end
      
      def extension extension = nil
        if extension
          @extension = extension.to_s
        else
          @extension ||= CodeRay::Scanners[lang].file_extension.to_s
        end
      end
    end
    
    # Create only once, for speed
    Tokenizer = CodeRay::Encoders[:debug].new
    
    def test_ALL
      puts
      puts '    >> Testing '.magenta + self.class.name[/\w+$/].cyan +
        ' scanner <<'.magenta
      puts
      
      time_for_lang = Benchmark.realtime do
        scanner = CodeRay::Scanners[self.class.lang].new
        raise "No Scanner for #{self.class.lang} found!" if scanner.is_a? CodeRay::Scanners[nil]
        max = ENV.fetch('max', DEFAULT_MAX).to_i
        
        random_test scanner, max unless ENV['norandom'] || ENV['only']
        
        unless ENV['noexamples']
          examples_test scanner, max
        end
      end
      
      puts 'Finished in '.green + '%0.2fs'.white % time_for_lang + '.'.green
    end
    
    def examples_test scanner, max
      self.class.dir do
        extension = 'in.' + self.class.extension
        path = "test/scanners/#{File.basename(Dir.pwd)}/*.#{extension}"
        print 'Loading examples in '.green + path.cyan + '...'.green
        examples = Dir["*.#{extension}"]
        if examples.empty?
          puts "No examples found!".red
        else
          puts '%d'.yellow % examples.size + " example#{'s' if examples.size > 1} found.".green
        end
        for example_filename in examples
          name = File.basename(example_filename, ".#{extension}")
          next if ENV['lang'] && ENV['only'] && ENV['only'] != name
          filesize_in_kb = File.size(example_filename) / 1024.0
          print '%15s'.cyan % name + ' %6.1fK: '.yellow % filesize_in_kb
          
          tokens = example_test example_filename, name, scanner, max
          
          if time = @time_for_encoding
            kilo_tokens_per_second = tokens.size / time / 1000
            print 'finished in '.green + '%5.2fs'.white % time
            if filesize_in_kb > 1
              print ' ('.green + '%4.0f Ktok/s'.white % kilo_tokens_per_second + ')'.green
            end
            @time_for_encoding = nil
          end
          puts '.'.green
        end
      end
    end
    
    def example_test example_filename, name, scanner, max
      if File.size(example_filename) > MAX_CODE_SIZE_TO_TEST and not ENV['only']
        print 'too big, '
        return
      end
      code = File.open(example_filename, 'rb') { |f| break f.read }
      
      incremental_test scanner, code, max unless ENV['noincremental']
      
      unless ENV['noshuffled'] or code.size < [0].pack('Q').size
        shuffled_test scanner, code, max
      else
        print '-skipped- '.concealed
      end
      
      tokens, ok, changed_lines = complete_test scanner, code, name
      
      identity_test scanner, tokens
      
      unless ENV['nohighlighting'] or (code.size > MAX_CODE_SIZE_TO_HIGHLIGHT and not ENV['only'])
        highlight_test tokens, name, ok, changed_lines
      else
        print '-- skipped -- '.concealed
      end
      tokens
    end
    
    def random_test scanner, max
      print "Random test...".yellow
      okay = true
      for size in (0..max).progress
        srand size + 17
        scanner.string = Array.new(size) { rand 256 }.pack 'c*'
        begin
          scanner.tokenize
        rescue
          assert_nothing_raised "Random test failed at #{size} #{RUBY_VERSION < '1.9' ? 'bytes' : 'chars'}" do
            raise
          end if ENV['assert']
          okay = false
          break
        end
      end
      print "\b" * 'Random test...'.size
      print 'Random test'.green_or_red(okay)
      puts ' - finished.'.green
    end
    
    def incremental_test scanner, code, max
      report 'incremental' do
        okay = true
        for size in (0..max).progress
          break if size > code.size
          scanner.string = code[0,size]
          begin
            scanner.tokenize
          rescue
            assert_nothing_raised "Incremental test failed at #{size} #{RUBY_VERSION < '1.9' ? 'bytes' : 'chars'}!" do
              raise
            end if ENV['assert']
            okay = false
            break
          end
        end
        okay
      end
    end
    
    def shuffled_test scanner, code, max
      report 'shuffled' do
        code_bits = code[0,max].unpack('Q*')  # split into quadwords...
        okay = true
        for i in (0..max / 4).progress
          srand i
          code_bits.shuffle!                     # ...mix...
          scanner.string = code_bits.pack('Q*')  # ...and join again
          begin
            scanner.tokenize
          rescue
            assert_nothing_raised 'shuffle test failed!' do
              raise
            end if ENV['assert']
            okay = false
            break
          end
        end
        okay
      end
    end
    
    def complete_test scanner, code, name
      print 'complete...'.yellow
      expected_filename = name + '.expected.' + Tokenizer.file_extension
      scanner.string = code
      
      tokens = result = nil
      @time_for_encoding = Benchmark.realtime do
        tokens = scanner.tokens
        result = Tokenizer.encode_tokens tokens
      end
      
      if File.exist?(expected_filename) && !(ENV['lang'] && ENV['new'] && name == ENV['new'])
        expected = File.open(expected_filename, 'rb') { |f| break f.read }
        ok = expected == result
        actual_filename = expected_filename.sub('.expected.', '.actual.')
        unless ok
          File.open(actual_filename, 'wb') { |f| f.write result }
          diff = expected_filename.sub(/\.expected\..*/, '.debug.diff')
          system "diff --unified=0 --text #{expected_filename} #{actual_filename} > #{diff}"
          changed_lines = []
          File.read(diff).scan(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/) do |offset, size|
            offset = offset.to_i
            size = (size || 1).to_i
            changed_lines.concat Array(offset...offset + size)
          end
        end
        
        assert(ok, "Scan error: unexpected output".red) if ENV['assert']
        
        print "\b" * 'complete...'.size
        print 'complete, '.green_or_red(ok)
      else
        File.open(expected_filename, 'wb') { |f| f.write result }
        print "\b" * 'complete...'.size, "new test, ".blue
        ok = true
      end
      
      return tokens, ok, changed_lines
    end
    
    def identity_test scanner, tokens
      report 'identity' do
        if scanner.instance_of? CodeRay::Scanners[:debug]
          okay = true
        else
          okay = scanner.code == tokens.text
          unless okay
            flunk 'identity test failed!' if ENV['assert']
          end
          okay
        end
      end
    end
    
    Highlighter = CodeRay::Encoders[:html].new(
      :tab_width => 2,
      :line_numbers => :table,
      :wrap => :page,
      :hint => :debug,
      :css => :class
    )
    
    def highlight_test tokens, name, okay, changed_lines
      report 'highlighting' do
        begin
          highlighted = Highlighter.encode_tokens tokens, { :highlight_lines => changed_lines }
        rescue
          flunk 'highlighting test failed!' if ENV['assert']
          return false
        end
        File.open(name + '.actual.html', 'w') { |f| f.write highlighted }
        FileUtils.copy(name + '.actual.html', name + '.expected.html') if okay
        true
      end
    end
    
    def report task
      print "#{task}...".yellow
      okay = yield
      print "\b" * "#{task}...".size
      print "#{task}, ".green_or_red(okay)
      okay
    end
  end
  
  class TestSuite
    @suite = Test::Unit::TestSuite.new 'CodeRay::Scanners'
    class << self
      
      def << sub_suite
        @suite << sub_suite
      end
      
      def load_suite name
        begin
          suite = File.join($mydir, name, 'suite.rb')
          require suite
        rescue LoadError
          $stderr.puts <<-ERR
          
      !! Suite #{suite} not found
          
          ERR
          false
        end
      end
      
      def check_env_lang
        for key in %w(only new)
          if ENV[key] && ENV[key][/^(\w+)\.([-\w_]+)$/]
            ENV['lang'] = $1
            ENV[key] = $2
          end
        end
      end
      
      def load
        ENV['only'] = ENV['new'] if ENV['new']
        check_env_lang
        subsuite = ARGV.find { |a| break $& if a[/^[^-].*/] } || ENV['lang']
        if subsuite
          load_suite(subsuite) or exit
        else
          Dir[File.join($mydir, '*', '')].sort.each do |suite|
            load_suite File.basename(suite)
          end
        end
      end
      
      def run
        load
        $VERBOSE = true
        $stdout.sync = true
        require 'test/unit/ui/console/testrunner'
        Test::Unit::UI::Console::TestRunner.run @suite
      end
    end
  end
  
end