module Redom
  class Proxy
    def initialize(conn, info, extra = {})
      @conn = conn
      @info = info
      @info[P_INFO_OID] = __id__ unless @info[P_INFO_OID]

      @solved = false
      @origin = nil
    end
    attr_reader :origin

    def method_missing(name, *args, &blck)
      return @origin.send(name, *args, &block) if @solved && !@origin.is_a?(Proxy)

      if blck
        @conn.sync
        return @origin.send(name, *args, &block)
      end

      proxy = Proxy.new(@conn, [nil, _info[P_INFO_OID], name, _arg(args)], {:backtrace => caller[0]})
      @conn._bulk proxy
      proxy
    end

    def sync
      unless @solved
        @conn.sync{}
      end
      @origin
    end

    def _info
      @info
    end

    def _origin(org)
      @solved = true
      @origin = org
    end

    private

    def _arg(arg)
      case arg
      when Proxy
        [TYPE_PROXY, arg._info[P_INFO_OID]]
      when Array
        arg.map! { |item|
          _arg(item)
        }
        [TYPE_ARRAY, arg]
      when Hash
        arg.each { |k, v|
          arg[k] = _arg(v)
        }
        arg
      when Method
        [TYPE_METHOD, @conn._cid, arg.name]
      when Symbol
        [TYPE_METHOD, @conn._cid, arg.to_s]
      else
        arg
      end
    end
  end
end