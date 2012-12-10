module Redom
  module Connection
    include Utils

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

    def sync(obj = nil)
      obj = _fid if obj == self
      if Connection === obj
        _dispatcher.run_task(obj, :sync, [_fid], nil)
        return
      end

      fid = obj ? obj : _fid
      stack = @proxies[fid]
      return if !stack || stack.empty?

      msg = []
      stack.each { |k, v|
        msg << v._info
      }

      rsp = Fiber.yield(msg)

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

      stack.clear

      on_error(error) if error
    end

    def _cid
      @ws.__id__
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