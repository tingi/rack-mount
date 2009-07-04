require 'strscan'

module Rack
  module Mount
    class Strexp < Regexp
      # Parses segmented string expression and converts it into a Regexp
      #
      #   Strexp.compile('foo')
      #     # => %r{^foo$}
      #
      #   Strexp.compile('foo/:bar', {}, ['/'])
      #     # => %r{^foo/(?<bar>[^/]+)$}
      #
      #   Strexp.compile(':foo.example.com')
      #     # => %r{^(?<foo>.+)\.example\.com$}
      #
      #   Strexp.compile('foo/:bar', {:bar => /[a-z]+/}, ['/'])
      #     # => %r{^foo/(?<bar>[a-z]+)$}
      #
      #   Strexp.compile('foo(.:extension)')
      #     # => %r{^foo(\.(?<extension>.+))?$}
      #
      #   Strexp.compile('src/*files')
      #     # => %r{^src/(?<files>.+)$}
      def initialize(str, requirements = {}, separators = [])
        return super(str) if str.is_a?(Regexp)

        re = Regexp.escape(str)
        requirements ||= {}

        normalize_requirements!(requirements, separators)
        parse_dynamic_segments!(re, requirements)
        parse_optional_segments!(re)

        super("^#{re}$")
      end

      private
        def normalize_requirements!(requirements, separators)
          requirements.each do |key, value|
            requirements[key] = value.is_a?(Regexp) ?
              value.source : Regexp.escape(value)
          end
          requirements.default ||= separators.any? ?
            "[^#{separators.join}]+" : '.+'
          requirements
        end

        def parse_dynamic_segments!(str, requirements)
          re, pos, scanner = '', 0, StringScanner.new(str)
          while scanner.scan_until(/(:|\\\*)([a-zA-Z_]\w*)/)
            pre, pos = scanner.pre_match[pos..-1], scanner.pos
            if pre =~ /(.*)\\\\$/
              re << $1 + scanner.matched
            else
              name = scanner[2].to_sym
              requirement = scanner[1] == ':' ?
                requirements[name] : '.+'
              re << pre + Const::REGEXP_NAMED_CAPTURE % [name, requirement]
            end
          end
          re << scanner.rest
          str.replace(re)
        end

        def parse_optional_segments!(str)
          re, pos, scanner = '', 0, StringScanner.new(str)
          while scanner.scan_until(/\\\(|\\\)/)
            pre, pos = scanner.pre_match[pos..-1], scanner.pos
            if pre =~ /(.*)\\\\$/
              re << $1 + scanner.matched
            elsif scanner.matched == '\\('
              re << pre + '('
            elsif scanner.matched == '\\)'
              re << pre + ')?'
            end
          end
          re << scanner.rest
          str.replace(re)
        end
    end
  end
end
