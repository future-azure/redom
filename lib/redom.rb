require 'json'
require 'logger'
require 'fiber'
require 'thread'

module Redom
  DEFAULT_OPTIONS = {
    :log => STDOUT,
    :log_level => 'info',
    :websocket_server => true,
    :worker => 5,
    :buff_size => 200,
    :host => '0.0.0.0',
    :port => 8080
  }

  REQ_HANDSHAKE          = 0
  REQ_METHOD_INVOCATION  = 1
  REQ_PROXY_RESULT       = 2

  IDX_REQUEST_TYPE     = 0
  # REQ_HANDSHAKE
  IDX_CONNECTION_CLASS = 1
  # REQ_METHOD_INVOCATION
  IDX_METHOD_NAME      = 1
  IDX_ARGUMENTS        = 2
  # REQ_PROXY_RESULT
  IDX_TASK_ID          = 1
  IDX_PROXY_RESULT     = 2

  TYPE_UNDEFINED = 0
  TYPE_PROXY     = 1
  TYPE_ARRAY     = 2
  TYPE_ERROR     = 3
  TYPE_METHOD    = 4

  T_INFO_METHOD_NAME = 0
  T_INFO_ARGUMENTS   = 1
  T_INFO_BLOCK       = 2

  P_INFO_OID  = 0
  P_INFO_RCVR = 1
  P_INFO_NAME = 2
  P_INFO_ARGS = 3

  module Utils
    @@logger = nil

    def self.logger=(logger)
      @@logger = logger
    end
    
    def self.server=(server)
      @@server = server
    end

    def _logger
      @@logger
    end
    
    def _server
      @@server
    end
  end

  # Redom Connection
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
      Redom.connections(filter)
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
      if Connection === obj
        _server.run_task(obj, :sync, [_fid], nil)
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
      @ws.send msg
    end
  end
  # -- Connection --

  class Connections
    include Utils
    include Enumerable

    def initialize(conns)
      @conns = conns
    end

    def each
      @conns.each { |conn|
        yield conn
      }
    end

    def method_missing(name, *args, &blck)
      @conns.each { |conn|
        _server.run_task(conn, name, args, blck)
      }
    end
  end

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
        @conn.sync
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
        [TYPE_METHOD, arg.name]
      when Symbol
        [TYPE_METHOD, arg.to_s]
      else
        arg
      end
    end
  end

  # Redom Server
  class Server
    include Utils

    def initialize(opts)
      if find_all_connection_classes.size == 0
        _logger.error 'No Redom::Connection class defined.'
        exit
      end

      @opts = opts
      @conns = Hash.new
      @tasks = Hash.new
      @pool = ThreadPool.new(@opts)
    end

    def run_task(conn, name, args, blck)
      task = Task.new(conn, @pool.worker, [name, args, blck])
      @tasks[task._id] = task
      task.run
    end

    def on_open(ws)
      _logger.debug "Connection established. ID='#{ws.__id__}'"
    end

    def on_message(ws, msg)
      _logger.debug "Received message. ID='#{ws.__id__}'\n#{msg}"
      req = JSON.parse(msg)
      case req[IDX_REQUEST_TYPE]
      when REQ_HANDSHAKE
        if cls = @conn_cls[req[IDX_CONNECTION_CLASS]]
          conn = cls.new._init(ws, @opts)
          @conns[ws.__id__] = conn
          task = Task.new(conn, @pool.worker, [:on_open, []])
          @tasks[task._id] = task
          task.run
        else
          _logger.error "Undefined Redom::Connection class '#{req[IDX_CONNECTION_CLASS]}'."
        end
      when REQ_METHOD_INVOCATION
        if conn = @conns[ws.__id__]
          req[IDX_ARGUMENTS].map! { |arg|
            if Array === arg
              case arg[0]
              when TYPE_PROXY
                  arg = Proxy.new(conn, [arg[1]])
              when TYPE_ARRAY
                  arg = arg[1]
              end
            end
            arg
          }
          task = Task.new(conn, @pool.worker, req[IDX_METHOD_NAME..-1])
          @tasks[task._id] = task
          task.run
        else
          _logger.error "Connection missing. ID='#{ws.__id__}'"
        end
      when REQ_PROXY_RESULT
        if task = @tasks[req[IDX_TASK_ID]]
          task.run req[IDX_PROXY_RESULT]
        else
          _logger.error "Task missing. ID='#{req[IDX_TASK_ID]}'"
        end
      else
        _logger.error "Undefined request type '#{req[IDX_REQUEST_TYPE]}'."
      end
    end

    def on_close(ws)
      _logger.debug "Connection closed. ID='#{ws.__id__}'"
      if conn = @conns[ws.__id__]
        task = Task.new(conn, @pool.worker, [:on_close, []])
        @tasks[task._id] = task
        task.run
        @conns.delete ws.__id__
      end
    end

    def on_error(ws, err)
      _logger.debug "Error occured. ID='#{ws.__id__}'"
    end

    def delete_task(task_id)
      @tasks.delete task_id
    end

    def connections(filter)
      case filter
      when Class
        Connections.new(@conns.values.select { |conn|
          filter === conn
        })
      when Connection
        Connections.new(@conns.values.select { |conn|
          filter == conn
        })
      else
        Connections.new(@conns.values)
      end
    end

    private

    def find_all_connection_classes
      @conn_cls = Hash.new
      ObjectSpace.each_object(Class).select { |cls|
        cls < Connection
      }.each { |cls|
        @conn_cls[cls.name] = cls
      }
    end
  end
  # -- Server --

  class Task
    include Utils

    def initialize(conn, worker, info)
      @conn = conn
      @worker = worker
      @info = info
      @results = []
    end

    def run(proxy_result = nil)
      @results << proxy_result if proxy_result
      @worker.do_task self
    end

    def resume
      if !@results.empty?
        result = @fiber.resume(@results.shift)
      else
        mthd = @conn.method(@info[T_INFO_METHOD_NAME])
        args = @info[T_INFO_ARGUMENTS]
        blck = @info[T_INFO_BLOCK]
        @fiber = Fiber.new do
          if mthd
            if blck
              mthd.call(*args, &blck)
            else
              mthd.call(*args)
            end
          else
            _logger.error "Method '#{@info[T_INFO_METHOD_NAME]}' is not defined in class '#{@conn.class}'."
            @conn.method(:on_error).call("No such method '#{@info[T_INFO_METHOD_NAME]}'.")
          end
          @conn.sync
          nil
        end
        result = @fiber.resume
      end

      if result
        @conn._send [_id, result].to_json
      else
        _server.delete_task _id
      end
    end

    def _id
      "T#{__id__}"
    end
  end

  # THread Pool
  class ThreadPool
    def initialize(opts)
      @workers = Array.new
      # @key_idx = Hash.new
      @idx = 0
      opts[:worker].times {
        @workers << Worker.new
        # @key_idx[@workers[-1].tid] = @workers.size - 1
      }
    end

    def worker
      @workers[(@idx += 1) == @workers.size ? @idx = 0 : @idx]
    end
  end
  # -- ThreadPool --

  # Worker
  class Worker
    include Utils

    def initialize
      @queue = Queue.new
      @thread = Thread.start do
        while task = @queue.pop
          begin
            task.resume
          rescue
            _logger.error "Task failed. ID='#{task.__id__}'\n"
            _logger.error $!.message
            $!.backtrace.each { |item|
              _logger.error item
            }
          end
        end
      end
    end

    def do_task(task)
      @queue.push task
    end
  end
  # -- Worker --

  class << self
    # Start Redom server
    # @param [Hash] opts Options
    def start(opts = {})
      opts = DEFAULT_OPTIONS.merge(opts)
      logger = Logger.new(opts[:log])
      logger.level = case opts[:log_level].downcase
      when 'fatal'
        Logger::FATAL
      when 'error'
        Logger::ERROR
      when 'warn'
        Logger::WARN
      when 'info'
        Logger::INFO
      when 'debug'
        Logger::DEBUG
      else
        Logger::FATAL
      end
      Utils.logger = logger
      @@server = Server.new(opts)
      Utils.server = @@server

      if opts[:websocket_server]
        require 'em-websocket'
        EventMachine.run {
          EventMachine::WebSocket.start(opts) { |ws|
            ws.onopen {
              on_open ws
            }

            ws.onmessage { |msg|
             on_message ws, msg 
            }

            ws.onclose {
              on_close ws
            }

            ws.onerror { |err|
              on_error ws, err
            }
          }
        }
      end
    end

    def stop
      @@server.stop
    end

    def on_open(ws)
      @@server.on_open(ws)
    end

    def on_message(ws, msg)
      @@server.on_message(ws, msg)
    end

    def on_close(ws)
      @@server.on_close(ws)
    end

    def on_error(ws, err)
      @@server.on_error(ws, err)
    end

    def connections(filter = nil)
      @@server.connections filter
    end
  end
end
