module CodeRay
	
	require 'coderay/helpers/plugin'

	# = Scanners
	# 
	# $Id$
	# 
	# This module holds the Scanner class and its subclasses.
	# For example, the Ruby scanner is named CodeRay::Scanners::Ruby
	# can be found in coderay/scanners/ruby.
	# 
	# Scanner also provides methods and constants for the register
	# mechanism and the [] method that returns the Scanner class
	# belonging to the given lang.
	#
	# See PluginHost.
	module Scanners
		extend PluginHost
		plugin_path 'coderay/scanners'

		require 'strscan'

		# = Scanner
		#
		# The base class for all Scanners.
		#
		# It is a subclass of Ruby's great +StringScanner+, which
		# makes it easy to access the scanning methods inside.
		#
		# It is also +Enumerable+, so you can use it like an Array of
		# Tokens:
		# 
		#   require 'coderay'
		#   
		#   c_scanner = CodeRay::Scanners[:c].new "if (*p == '{') nest++;"
		#   
		#   for text, kind in c_scanner
		#     puts text if kind == :operator
		#   end
		#   
		#   # prints: (*==)++;
		# 
		# OK, this is a very simple example :)
		# You can also use +map+, +any?+, +find+ and even +sort_by+,
		# if you want.
		class Scanner < StringScanner
			extend Plugin
			plugin_host Scanners

			# Raised if a Scanner fails while scanning
			ScanError = Class.new(Exception)

			require 'coderay/helpers/scanner_helper'

			# The default options for all scanner classes.
			# 
			# Define @default_options for subclasses.
			DEFAULT_OPTIONS = { :stream => false }

			class << self
				# Register the scanner class for all
				# +langs+.
				#
				# See Scanners.register.
				def register_for *langs
					Scanners.register self, *langs
				end

				# Returns if the Scanner can be used in streaming mode.
				def streamable?
					is_a? Streamable
				end

			end

=begin
## Excluded for speed reasons; protected seems to make methods slow.

# Save the StringScanner methods from being called.
# This would not be useful for highlighting.
	strscan_public_methods =
		StringScanner.instance_methods -
		StringScanner.ancestors[1].instance_methods
	protected(*strscan_public_methods)
=end

			# Create a new Scanner.
			#
			# * +code+ is the input String and is handled by the superclass
			#   StringScanner.
			# * +options+ is a Hash with Symbols as keys.
			#   It is merged with the default options of the class (you can
			#   overwrite default options here.)
			# * +block+ is the callback for streamed highlighting.
			#
			# If you set :stream to +true+ in the options, the Scanner uses a
			# TokenStream with the +block+ as callback to handle the tokens.
			#
			# Else, a Tokens object is used.
			def initialize code, options = {}, &block
				@options = self.class::DEFAULT_OPTIONS.merge options
				raise "I am only the basic Scanner class. I can't scan "\
					"anything. :( Use my subclasses." if self.class == Scanner

				# I love this hack. It seems to silence
				# all dos/unix/mac newline problems.
				super code.gsub(/\r\n?/, "\n")

				if @options[:stream]
					warn "warning in CodeRay::Scanner.new: :stream is set, "\
						"but no block was given" unless block_given?
					raise NotStreamableError, self unless kind_of? Streamable
					@tokens = TokenStream.new(&block)
				else
					warn "warning in CodeRay::Scanner.new: Block given, "\
						"but :stream is #{@options[:stream]}" if block_given?
					@tokens = Tokens.new
				end
			end

			# More mnemonic accessor name for the input string.
			alias code string

			# Scans the code and returns all tokens in a Tokens object.
			def tokenize options = {}
				options = @options.merge({}) #options
				if @options[:stream]  # :stream must have been set already
					reset ## what is this for?
					scan_tokens @tokens, options
					@tokens
				else
					@cached_tokens ||= scan_tokens @tokens, options
				end
			end

			# You can also see tokenize as a read-only attribute
			alias tokens tokenize

			# Traverses the tokens.
			def each &block
				raise ArgumentError, 
					'Cannot traverse TokenStream.' if @options[:stream]
				tokens.each(&block)
			end
			include Enumerable

			# The current line position of the scanner.
			#
			# Beware, this is implemented inefficiently. It should be used
			# for debugging only.
			def line
				string[0..pos].count("\n") + 1
			end

		protected

			# This is the central method, and commonly the only one a
			# subclass implements.
			# 
			# Subclasses must implement this method; it must return +tokens+
			# and must only use Tokens#<< for storing scanned tokens!
			def scan_tokens tokens, options
				raise NotImplementedError,
					"#{self.class}#scan_tokens not implemented."
			end

			# Scanner error with additional status information
			def raise_inspect msg, tokens, ambit = 30
				raise ScanError, <<-EOE % [


***ERROR in %s: %s

tokens:
%s

current line: %d  pos = %d
matched: %p
bol? = %p,  eos? = %p

surrounding code:
%p  ~~  %p


***ERROR***

				EOE
				File.basename(caller[0]),
				msg,
				tokens.last(10).map { |t| t.inspect }.join("\n"),
				line, pos,
				matched, bol?, eos?,
				string[pos-ambit,ambit],
				string[pos,ambit],
				]
			end

		end

	end
end

# vim:sw=2:ts=2:noet:tw=78
