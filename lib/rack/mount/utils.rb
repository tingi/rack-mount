require 'rack/mount/regexp_with_named_groups'
require 'strscan'

module Rack
  module Mount
    # Private utility methods used throughout Rack::Mount.
    module Utils
      # Normalizes URI path.
      #
      # Strips off trailing slash and ensures there is a leading slash.
      #
      #   normalize_path("/foo")  # => "/foo"
      #   normalize_path("/foo/") # => "/foo"
      #   normalize_path("foo")   # => "/foo"
      #   normalize_path("")      # => "/"
      def normalize_path(path)
        path = "/#{path}"
        path.squeeze!(Const::SLASH)
        path.sub!(%r'/+$', Const::EMPTY_STRING)
        path = Const::SLASH if path == Const::EMPTY_STRING
        path
      end
      module_function :normalize_path

      # Removes trailing nils from array.
      #
      #   pop_trailing_nils!([1, 2, 3])           # => [1, 2, 3]
      #   pop_trailing_nils!([1, 2, 3, nil, nil]) # => [1, 2, 3]
      #   pop_trailing_nils!([nil])               # => []
      def pop_trailing_nils!(ary)
        while ary.length > 0 && ary.last.nil?
          ary.pop
        end
        ary
      end
      module_function :pop_trailing_nils!

      # Determines whether the regexp must match the entire string.
      #
      #   regexp_anchored?(/^foo$/) # => true
      #   regexp_anchored?(/foo/)   # => false
      #   regexp_anchored?(/^foo/)  # => false
      #   regexp_anchored?(/foo$/)  # => false
      def regexp_anchored?(regexp)
        regexp.source =~ /^\^.*\$$/ ? true : false
      end
      module_function :regexp_anchored?

      # Returns static string source of Regexp if it only includes static
      # characters and no metacharacters. Otherwise the original Regexp is
      # returned.
      #
      #   extract_static_regexp(/^foo$/)      # => "foo"
      #   extract_static_regexp(/^foo\.bar$/) # => "foo.bar"
      #   extract_static_regexp(/^foo|bar$/)  # => /^foo|bar$/
      def extract_static_regexp(regexp)
        if regexp.is_a?(String)
          regexp = Regexp.compile("^#{regexp}$")
        end

        source = regexp.source
        if regexp_anchored?(regexp)
          source.sub!(/^\^(.*)\$$/, '\1')
          unescaped_source = source.gsub(/\\/, Const::EMPTY_STRING)
          if source == Regexp.escape(unescaped_source) &&
              Regexp.compile("^(#{source})$") =~ unescaped_source
            return unescaped_source
          end
        end
        regexp
      end
      module_function :extract_static_regexp

      if Const::SUPPORTS_NAMED_CAPTURES
        NAMED_CAPTURE_REGEXP = /\?<([^>]+)>/.freeze
      else
        NAMED_CAPTURE_REGEXP = /\?:<([^>]+)>/.freeze
      end

      # Strips shim named capture syntax and returns a clean Regexp and
      # an ordered array of the named captures.
      #
      #   extract_named_captures(/[a-z]+/)          # => /[a-z]+/, []
      #   extract_named_captures(/(?:<foo>[a-z]+)/) # => /([a-z]+)/, ['foo']
      #   extract_named_captures(/([a-z]+)(?:<foo>[a-z]+)/)
      #     # => /([a-z]+)([a-z]+)/, [nil, 'foo']
      def extract_named_captures(regexp)
        options = regexp.is_a?(Regexp) ? regexp.options : nil
        source = Regexp.compile(regexp).source
        names, scanner = [], StringScanner.new(source)

        while scanner.skip_until(/\(/)
          if scanner.scan(NAMED_CAPTURE_REGEXP)
            names << scanner[1]
          else
            names << nil
          end
        end

        source.gsub!(NAMED_CAPTURE_REGEXP, Const::EMPTY_STRING)
        return Regexp.compile(source, options), names
      end
      module_function :extract_named_captures

      class Capture < Array #:nodoc:
        attr_reader :name, :optional
        alias_method :optional?, :optional

        def initialize(*args)
          options = args.last.is_a?(Hash) ? args.pop : {}

          @name = options.delete(:name)
          @name = @name.to_s if @name

          @optional = options.delete(:optional) || false

          super(args)
        end

        def ==(obj)
          @name == obj.name && @optional == obj.optional && super
        end

        def optionalize!
          @optional = true
          self
        end

        def named?
          name && name != Const::EMPTY_STRING
        end

        def to_s
          source = "(#{join})"
          source << '?' if optional?
          source
        end

        def freeze
          each { |e| e.freeze }
          super
        end
      end

      def extract_regexp_parts(regexp)
        unless regexp.is_a?(RegexpWithNamedGroups)
          regexp = RegexpWithNamedGroups.new(regexp)
        end

        if regexp.source =~ /\?<([^>]+)>/
          regexp, names = extract_named_captures(regexp)
        else
          names = regexp.names
        end
        source = regexp.source

        source =~ /^\^/ ? source.gsub!(/^\^/, Const::EMPTY_STRING) :
          raise(ArgumentError, "#{source} needs to match the start of the string")

        scanner = StringScanner.new(source)
        stack = [[]]

        capture_index = 0
        until scanner.eos?
          char = scanner.getch
          cur  = stack.last

          escaped = cur.last.is_a?(String) && cur.last[-1, 1] == '\\'

          if escaped
            cur.push('') unless cur.last.is_a?(String)
            cur.last << char
          elsif char == '('
            name = names[capture_index]
            capture = Capture.new(:name => name)
            capture_index += 1
            cur.push(capture)
            stack.push(capture)
          elsif char == ')'
            capture = stack.pop
            if scanner.peek(1) == '?'
              scanner.pos += 1
              capture.optionalize!
            end
          elsif char == '$'
            cur.push(Const::EOS_KEY)
          else
            cur.push('') unless cur.last.is_a?(String)
            cur.last << char
          end
        end

        result = stack.pop
        result.each { |e| e.freeze }
        result
      end
      module_function :extract_regexp_parts

      def analysis_keys(possible_key_set)
        keys = {}
        possible_key_set.each do |possible_keys|
          possible_keys.each do |key, value|
            keys[key] ||= 0
            keys[key] += 1
          end
        end
        if keys.values.size > 0
          avg_size = keys.values.inject(0) { |sum, n| sum =+ n } / keys.values.size
        else
          avg_size = 0
        end

        keys = keys.sort { |e1, e2| e1[1] <=> e2[1] }
        keys.reverse!
        keys = keys.select { |e| e[1] >= avg_size }
        keys.map! { |e| e[0] }
        keys
      end
      module_function :analysis_keys
    end
  end
end
