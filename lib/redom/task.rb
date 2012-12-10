module Redom
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
        _dispatcher.delete_task _id
      end
    end

    def _id
      "T#{__id__}"
    end
  end
end