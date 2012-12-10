module Redom
  class Worker
    include Utils

    def initialize
      @queue = Queue.new
    end
    
    def start
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

    def stop
      @thread.kill
      @queue.clear
    end

    def do_task(task)
      @queue.push task
    end
  end
end