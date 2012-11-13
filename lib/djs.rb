require 'thread'
require 'fiber'
require 'em-websocket'
require 'json'
require 'opal'

module DJS
  INFO_RCVR = 'rcvr'
  INFO_TYPE = 'type'
  INFO_NAME = 'name'
  INFO_ARGS = 'args'
  INFO_BLCK = 'blck'
  INFO_PRXS = 'prxs'
  INFO_OID  = 'oid'
  INFO_CID  = 'cid'
  INFO_TID  = 'tid'
  INFO_FID  = 'fid'
  INFO_PRX  = 'prx'
  INFO_ORG  = 'org'
  INFO_MLT  = 'mlt'

  OPT_HOST      = :host
  OPT_PORT      = :port
  OPT_DEBUG     = :debug
  OPT_BUFF_SIZE = :buff_size
  OPT_WORKERS   = :workers

  TERMINAL = '\x00'

  # Proxy types
  METHOD_INVOCATION       = 1
  PROPERTY_ASSIGNMENT     = 2
  EVENTHANDLER_DEFINITION = 3
  EVENTHANDLER_INVOCATION = 4
  PROXY_RESPONSE          = 5

  # Object type
  TYPE_PRIMITIVE = 1
  TYPE_OBJECT    = 2
  TYPE_UNDEFINED = 3
  TYPE_ERROR     = 4
  TYPE_ARRAY     = 5
  TYPE_HASH      = 6
  TYPE_FUNCTION  = 7

  SYNC_METHOS = [:to_i, :to_f, :to_b, :to_a, :to_h]

  def self.start(klass = Connection, options = {})
    @@server = Server.new(klass, options)
    Connection.server = @@server
    @@server.run
  end

  def self.stop
    @@server.stop
  end
  
  def self.connections
    @@server.connection_filter
  end

  class Server
    DEFAULT_OPTIONS = {
      OPT_HOST => "0.0.0.0",
      OPT_PORT => 8080,
      OPT_DEBUG => false,
      OPT_WORKERS => 5
    }

    def initialize(klass, options)
      @klass = klass
      @opts = DEFAULT_OPTIONS.merge(options)
      @conns = Hash.new
      @connection_filter = ConnectionFilter.new(@conns)
      @conn_seq = 0
      @pool = ThreadPool.new(@opts)
    end

    attr_reader :connection_filter

    def run
      EventMachine.run {
        @pool.start
        EventMachine::WebSocket.start(@opts) { |ws|
          ws.onopen {
            cid = "c#{@conn_seq += 1}"
            conn = @conns[cid] = @klass.new(cid, ws, @opts)
            add_task(conn, {INFO_TYPE => METHOD_INVOCATION, INFO_NAME => :on_open, INFO_ARGS => []})
          }
          ws.onmessage { |msg|
            proxy = JSON.parse(msg)
            cid = proxy[INFO_CID]
            # TODO Error? if conn not exist
            if conn = @conns[cid]
              case proxy[INFO_TYPE]
              when METHOD_INVOCATION
                args = Array.new
                proxy[INFO_ARGS].each { |arg|
                  case arg[0]
                  when TYPE_PRIMITIVE
                    args << arg[1]
                  when TYPE_OBJECT
                    args << ProxyObject.new(conn, {INFO_OID => arg[1]})
                  end
                }
                proxy[INFO_ARGS] = args
                add_task(conn, proxy)
              when PROXY_RESPONSE
                resume(conn, proxy)
              end
            end
          }
          ws.onclose {
            @conns.each { |cid, conn|
              if conn.ws == ws
                add_task(conn, {INFO_TYPE => METHOD_INVOCATION, INFO_NAME => :on_close, INFO_ARGS => []})
                break
              end
            }
          }
          ws.onerror { |error|
            @conns.each { |cid, conn|
              if conn.ws == ws
                add_task(conn, {INFO_TYPE => METHOD_INVOCATION, INFO_NAME => :on_error, INFO_ARGS => []})
                break
              end
            }
          }
        }
      }
    end
    
    def add_task(conn, task)
      @pool.add_task(conn, task)
    end

    def resume(conn, task)
      @pool.resume(conn, task)
    end

    def close(cid)
      @conns.delete(cid).close
    end
    
    def connections
      @conns.values
    end
  end
  # Server -end-

  class ConnectionFilter
    def self.server=(server)
      @@server = server
    end

    def initialize(connections)
      @connections = connections
    end

    def [](pattern)
      if pattern == "*"
        return self
      end
      ConnectionFilter.new(Hash.new)
    end
    
    def find(count = 1, &blk)
      
    end

    def method_missing(name, *args, &block)
      @connections.values.each { |conn|
        conn.rpc(name, *args)
      }
    end
  end
  # ConnectionFilter -end-

  class ProxyObject
    def initialize(conn, info, bcktrc = '')
      @conn = conn
      @info = info
      @origin = nil
      @solved = false
      @info[INFO_OID] = "s#{conn.prx_seq}" unless @info.key?(INFO_OID)
      @bcktrc = bcktrc
    end

    attr_accessor :origin, :solved, :info, :conn
    attr_reader :bcktrc

    def method_missing(name, *args, &block)
      if SYNC_METHOS.include? name
        obj = sync
        if ProxyObject === obj
          if name == :to_a || name == :to_h
            return obj
          elsif name == :to_b
            return obj && obj != false
          else
            # TODO Array, Hash
            raise RuntimeError.new("Type conversion error")
          end
        else
          if name == :to_b
            return obj && obj != false
          else
            return obj.method(name).call
          end
        end
      end

      if @solved
        return @origin.send(name, *args, &block)
      end

      if block
        @conn.add_proxy
        return @origin.send(name, *args, &block)
      end

      name = name.to_s
      type = METHOD_INVOCATION

      # Class. ex: _jsArray.new
      if name =~ /^_js[A-Z]/ && args.size == 0
        return ClassProxyObject.new(@conn, name, caller[0])
      end

      if name =~ /^.+=$/
        if args && !args.empty?
          name = name[0..-2]
          if Symbol === args[0]
            type = EVENTHANDLER_DEFINITION
          else
            type = PROPERTY_ASSIGNMENT
          end
        else
          raise "Argument required."
        end
      end

      proxy = ProxyObject.new(@conn, {INFO_TYPE => type, INFO_RCVR => @info[INFO_OID], INFO_NAME => name, INFO_ARGS => to_arg(args)}, caller[0])
      @conn.add_proxy proxy
      return proxy
    end

    def [](key)
      proxy = ProxyObject.new(@conn, {INFO_TYPE => METHOD_INVOCATION, INFO_RCVR => @info[INFO_OID], INFO_NAME => :[], INFO_ARGS => to_arg([key])}, caller[0])
      @conn.add_proxy proxy
      return proxy
    end

    def []=(key, value)
      proxy = ProxyObject.new(@conn, {INFO_TYPE => METHOD_INVOCATION, INFO_RCVR => @info[INFO_OID], INFO_NAME => :[]=, INFO_ARGS => to_arg([key, value])}, caller[0])
      @conn.add_proxy proxy
      return proxy
    end

    def sync
      return @origin if @solved
      @conn.add_proxy
      return @solved ? @origin : self
    end
    
    def origin=(info)
      @solved = true
      case info[INFO_TYPE]
      when TYPE_PRIMITIVE
        @origin = info[INFO_ORG]
      when TYPE_OBJECT
        @origin = ProxyObject.new(@conn, {INFO_OID => info[INFO_OID]})
      end
    end

    alias :org_to_s :to_s
    def to_s
      obj = sync
      if ProxyObject === obj
        obj.org_to_s
      else
        obj.to_s 
      end
    end
    
    def to_arg(arg)
      case arg
      when ProxyObject
        [TYPE_OBJECT, arg.info[INFO_OID]]
      when Array
        arg.map! { |item|
          to_arg(item)
        }
        [TYPE_ARRAY, arg]
      when Hash
        arg.each { |k, v|
          arg[k] = to_arg(v)
        }
        [TYPE_HASH, arg]
      when Method
        [TYPE_FUNCTION, arg.name.to_s]
      else
        [TYPE_PRIMITIVE, arg]
      end
    end
  end
  # ProxyObject -end-

  class EventProxyObject < ProxyObject
    def initialize(conn, event_id)
      super(conn, {INFO_RCVR => "EVENTS[#{event_id}]"})
    end
  end

  class RpcProxyObject < ProxyObject
    def initialize(conn)
      super(conn, {INFO_RCVR => 'rpc', INFO_NAME => conn.__id__})
    end
  end

  class Argument < ProxyObject
    def initialize(conn, name)
      @name = name
      super(conn, {INFO_RCVR => self})
    end
  end

  class ClassProxyObject < ProxyObject
    def initialize(conn, name, caller)
      @name = name[1, name.length]
      super(conn, {INFO_RCVR => self}, caller)
    end

    def new(*args)
      proxy = ProxyObject.new(@conn, {INFO_RCVR => 'new', INFO_NAME => @name, INFO_ARGS => args}, caller[0])
      @conn.add_proxy proxy
      proxy.info[INFO_RCVR] = self
      return proxy
    end
  end

  class Connection
    DEFAULT_OPTIONS = {
      OPT_BUFF_SIZE => 200
    }

    def self.server=(server)
      @@server = server
    end

    def initialize(cid, ws, options)
      @cid = cid
      @ws = ws
      @opts = DEFAULT_OPTIONS.merge(options)
      @proxies = Hash.new
      @registered_function = Array.new
      @prx_seq = 0
      @queues = Hash.new
      @fibers = Hash.new
    end

    attr_reader :cid, :ws

    def close
      @ws.close_websocket
    end

    def connections
      @@server.connections
    end

    def process(proxy)
      result = nil
      fid = nil
      type = proxy[INFO_TYPE]
      case type
      when METHOD_INVOCATION
        name = proxy[INFO_NAME]
        args = proxy[INFO_ARGS]
        blck = proxy[INFO_BLCK]
        fiber = Fiber.new do
          if defined? name
            if blck
              method(name).call(*args)
            else
              method(name).call(*args, &blck)
            end
          else
            # TODO error message
            method(:on_error).call("No such method \"#{name.to_s}\".")
          end
          add_proxy
          TERMINAL
        end
        fid = _fid(fiber.__id__)
        @fibers[fid] = fiber
        @queues[fid] = Queue.new
        result = fiber.resume
      when PROXY_RESPONSE
        fid = proxy[INFO_FID]
        rsp = proxy[INFO_PRX]
        result = @fibers[fid].resume(rsp)
      end

      if result == TERMINAL
        @fibers.delete(fid)
        @queues.delete(fid)
      end
    end

    def send(msg)
      @ws.send({INFO_CID => @cid, INFO_TID => _tid, INFO_FID => _fid, INFO_PRXS => msg}.to_json)
    end

    def add_proxy(proxy = nil)
      if @register
        @register << proxy.info
      else
        fid = _fid
        if proxy
          stack = @proxies[fid] || @proxies[fid] = Hash.new
          stack[proxy.info[INFO_OID]] = proxy
        end
        if !proxy || stack.size == @opts[OPT_BUFF_SIZE]
          flush
        end
      end
    end

    def sync
      add_proxy
    end

    def flush
      stack = @proxies[_fid]
      return if !stack || stack.empty?

      error = nil

      infos = Array.new
      stack.each { |k, v|
        infos << v.info
      }
      send(infos)
      rsp = Fiber.yield
      while info = rsp.shift
          case info[INFO_TYPE]
          when TYPE_UNDEFINED
            proxy = stack[info[INFO_OID]]
            rcvr = stack[proxy.info[INFO_RCVR]]
            if rcvr.respond_to?(proxy.info[INFO_NAME])
              result = rcvr.send(proxy.info[INFO_NAME], *proxy.info[INFO_ARGS])
              proxy.origin = {INFO_TYPE => TYPE_PRIMITIVE, INFO_ORG => result}
            else
              error = NoMethodError.new("undefined method `#{proxy.info[INFO_NAME]}'")
              # TODO on error clear stack???
            end
            # TODO ????????????
            # rsp = Fiber.yield(json)
          when TYPE_ARRAY
            # TODO
            p '###############################'
          when TYPE_ERROR
            p "++++++++++ ERROR ++++++++++++++"
          else
            proxy = stack[info[INFO_OID]]
            proxy.origin = info
          end
      end

      stack.clear

      on_error(error) if error
    end

    # Default Event handler
    def on_open; end
    def on_close; end
    def on_message(msg); end
    def on_error(err); end

    # Root Javascript Object
    def window
      ProxyObject.new(self, {INFO_OID => :window, INFO_RCVR => :window})
    end
    
    def document
      ProxyObject.new(self, {INFO_OID => :document, INFO_RCVR => :document})
    end

    def js_eval(src)
      window.eval src
    end

    def djs_eval(src)
      window.eval(Opal.parse(src))
    end

    def method_missing(name, *args, &blk)
      window.method_missing(name, *args)
    end
    
    def rpc(name, *args, &blk)
      @@server.add_task(self, {INFO_TYPE => METHOD_INVOCATION, INFO_NAME => name, INFO_ARGS => args, INFO_BLCK => blk})
    end
    
    def prx_seq
      @prx_seq += 1
    end
    
    def _tid
      "t#{Thread.current.__id__}"
    end

    def _fid(fid = nil)
      fid ? "f#{fid}" : "f#{Fiber.current.__id__}"
    end
  end
  # Connection -end-
  
  class ThreadPool
    def initialize(opt)
      @workers = Array.new
      @tid_idx = Hash.new
      @count = opt[OPT_WORKERS]
      @count.times {
        @workers << Worker.new
      }
      @index = 0
    end

    def start
      idx = -1
      @workers.each { |worker|
        worker.start
        @tid_idx[worker._tid] = (idx += 1)
      }
    end

    def worker
      @workers[(@index += 1) == @count ? @index = 0 : @index]
    end

    def add_task(conn, task)
      worker.do_task(conn, task)
    end
    
    def resume(conn, task)
      @workers[@tid_idx[task[INFO_TID]]].do_task(conn, task) if @tid_idx[task[INFO_TID]]
    end
  end
  # ThreadPool -end-
  
  class Worker
    def initialize
      @queue = Queue.new
    end

    def start
      @thread = Thread.start do
        begin
          while work = @queue.pop
            work[0].process(work[1])
          end
        rescue
          # TODO error
          p $!
          p $!.backtrace
        end
      end
    end

    def stop
      @thread.stop
    end

    def do_task(conn, task)
      @queue.push([conn, task])
    end

    def _tid
      "t#{@thread.__id__}"
    end
  end
  # Worker -end-
end
