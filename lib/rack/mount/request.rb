module Rack
  module Mount
    class Request
      def initialize(env)
        @env = env
      end

      def method
        @method ||= @env[Route::HTTP_REQUEST_METHOD] || Route::HTTP_GET
      end

      def path
        @path ||= @env[Route::HTTP_PATH_INFO] || "/"
      end

      def first_segment
        split_segments! unless @first_segment
        @first_segment
      end

      def second_segment
        split_segments! unless @second_segment
        @second_segment
      end

      private
        def split_segments!
          _, @first_segment, @second_segment = path.split(%r{/|\.|\?})
        end
    end
  end
end
