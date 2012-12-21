module Redom
  module Connection
    include Utils

    class Sender
      def initialize(conn, async = false)
        @conn = conn
        @async = async
      end

      def method_missing(name, *args, &blck)
        if @async
          @conn._dispatcher.run_task(@conn, name, args, blck)
          nil
        else
          result = @conn.send(name, *args, &blck)
          @conn.sync{}
          result
        end
      end
    end

    # Default event handlers
    def on_open; end
    def on_close; end
    def on_error(err); end

    # Proxy of browser objects
    def window
      Proxy.new(self, [:window], {:backtrace => caller[0]})
    end
    def document
      Proxy.new(self, [:document], {:backtrace => caller[0]})
    end

    def method_missing(name, *args, &blck)
      window.method_missing(name, *args, &blck)
    end

    def connections(filter = self.class)
      _dispatcher.connections(filter)
    end

    # Initialization
    def _init(ws, opts)
      @ws = ws
      @proxies = Hash.new
      @buff_size = opts[:buff_size]
      @sync = Sender.new(self, false)
      @async = Sender.new(self, true)
      self
    end

    def _bulk(proxy)
      fid = _fid
      stack = @proxies[fid] || @proxies[fid] = Hash.new
      stack[proxy._info[P_INFO_OID]] = proxy
      if stack.size == @buff_size
        sync
      end
    end

    def sync(&blck)
      return @sync unless blck

      fid = _fid
      stack = @proxies[fid]
      return if !stack || stack.empty?

      msg = []
      stack.each { |k, v|
        msg << v._info
      }

      rsp = Fiber.yield([self, msg])

      error = nil
      while result = rsp.shift
        proxy = stack[result[0]]
        if Array === result[1]
          case result[1][0]
          when TYPE_UNDEFINED
            # TODO
          when TYPE_PROXY
            proxy._origin proxy
          when TYPE_ERROR
            # TODO
          end
        else
          proxy._origin result[1]
        end
      end

      vars = (eval('local_variables', blck.binding) - [:_]).map { |v|
        "#{v} = map[#{v}.__id__].origin if Redom::Proxy === #{v} && map.key?(#{v}.__id__)"
      }.join("\n")
      set_var = eval %Q{
        lambda { |map|
          #{vars}
        }
      }, blck.binding
      set_var.call stack

      stack.clear

      on_error(error) if error

      nil
    end

    def async(block = nil, &blck)
      return @async unless block || blck

      if block
        block.call
      else
        _dispatcher.run_task(self, :async, blck)
      end

      nil
    end

    def parse(str, file='(file)')
      Parser.new(self).parse str, file
    end

    def _on_open
      _bulk Proxy.new(self, [nil, nil, nil, _cid])
      on_open
    end

    def _cid
      "#{@ws.__id__}@#{__id__}"
    end

    def _fid
      "F#{Fiber.current.__id__}"
    end

    def _send(msg)
      _logger.debug "Message sent. ID='#{@ws.__id__}'\n#{msg}"
      @ws.send msg
    end
  end
end