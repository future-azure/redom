module Redom
  class Dispatcher
    include Utils

    def initialize(opts)
      if find_all_connection_classes.size == 0
        _logger.warn 'No Redom::Connection class defined.'
      end

      @opts = opts
      @conns = Hash.new
      @tasks = Hash.new
      @pool = ThreadPool.new(@opts)
      @pool.start
    end

    def stop
      @pool.stop
    end

    def run_task(conn, name, args = [], blck = nil)
      task = Task.new(conn, @pool.worker, [name, args, blck])
      @tasks[task._id] = task
      task.run
    end

    def on_open(ws)
      _logger.debug "Connection established. ID='#{ws.__id__}'"
    end

    def on_message(ws, msg)
      _logger.debug "Message received. ID='#{ws.__id__}'\n#{msg}"
      req = JSON.parse(msg)
      case req[IDX_REQUEST_TYPE]
      when REQ_HANDSHAKE
        if cls = @conn_cls[req[IDX_CONNECTION_CLASS]]
          conn = cls.new._init(ws, @opts)
          @conns["#{ws.__id__}@#{conn.__id__}"] = conn
          run_task(conn, :_on_open)
        else
          _logger.error "Undefined Redom::Connection class '#{req[IDX_CONNECTION_CLASS]}'."
        end
      when REQ_METHOD_INVOCATION
        if conn = @conns[req[IDX_CONNECTION_ID]]
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
          run_task(conn, req[IDX_METHOD_NAME], req[IDX_ARGUMENTS])
        else
          _logger.error "Connection missing. ID='#{req[IDX_CONNECTION_ID]}'"
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
        run_task(conn, :on_close)
        @conns.delete ws.__id__
      end
    end

    def on_error(ws, err)
      _logger.debug "Error occured. ID='#{ws.__id__}'"
    end

    def delete_task(task_id)
      @tasks.delete task_id
    end

    def connections(filter = nil)
      if filter
        @conns.values.select { |conn|
          filter === conn
        }
      else
        @conns.values
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
end