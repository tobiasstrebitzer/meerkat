module Meerkat
  class RackAdapter
    attr_accessor :retry
    attr_accessor :timeout
    attr_accessor :keep_alive

    def initialize(app = nil, &blk)
      @retry = 3000
      @timeout = false
      @keep_alive = 20
      blk.call(self) if blk
    end

    def call(env)
      body = DeferrableBody.new

      EM.next_tick { 
        env['async.callback'].call [200, {'Content-Type' => 'text/event-stream'}, body] 
      }
      EM.next_tick { body << "retry: #{@retry}\n" }
      EM.add_periodic_timer(@keep_alive) { body << ":\n" }
      EM.add_timer(@timeout) { body.succeed } if @timeout

      path_info = Rack::Utils.unescape env["PATH_INFO"]
      sub = Meerkat.subscribe(path_info) do |topic, json|
        body << "event: #{topic}\n"
        body << "data: #{json}\n\n"
      end
      body.errback do
        Meerkat.unsubscribe sub
      end

      [-1, {}, []]
    end

    class DeferrableBody
      include EventMachine::Deferrable

      def call(body)
        body.each do |chunk|
          @body_callback.call(chunk)
        end
      end

      def <<(str)
        call([str])
      end

      def each(&blk)
        @body_callback = blk
      end
    end
  end
end
