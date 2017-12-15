module CodeRay
module Scanners
  
  # Scanner for JSON (JavaScript Object Notation).
  #
  # See http://json.org/ for a definition of the JSON lexic/grammar.
  class JSON5 < RuleBasedScanner
    
    register_for :json5
    file_extension 'json'
    
    KINDS_NOT_LOC = [
      :float, :char, :content, :delimiter,
      :error, :integer, :operator, :value,
    ]  # :nodoc:
    
    ESCAPE = / [bfnrt\\"\/] /x  # :nodoc:
    UNICODE_ESCAPE = / u[a-fA-F0-9]{4} /x  # :nodoc:
    KEY = / (?> (?: [^\\"]+ | \\. )* ) " \s* : /mx
    
    state :initial do
      on %r/ \s+ /x, :space
      
      on %r/ [:,\[{\]}] /x, :operator
      
      on %r/ " (?=#{KEY}) /x, push(:key),    :delimiter
      on %r/ " /x,            push(:string), :delimiter
      
      on %r/ true | false | null /x, :value
      on %r/ -? (?: 0 | [1-9]\d* ) (?: \.\d+ (?: e[-+]? \d+ )? | e[-+]? \d+ ) /ix, :float
      on %r/ -? (?: 0 | [1-9]\d* ) (?: e[+-] \d+ )? /ix, :integer
    end
    
    state :key, :string do
      on %r/ [^\\"]+ /x, :content
      
      on %r/ " /x, :delimiter, pop
      
      on %r/ \\ (?: #{ESCAPE} | #{UNICODE_ESCAPE} ) /x, :char
      on %r/ \\. /mx, :content
      on %r/ \\ /x, :error, pop
    end
    
    def close_groups encoder, states
      if [:string, :key].include? states.last
        encoder.end_group states.last
      end
    end
    
  end
  
end
end
