module Redom
  class ThreadPool
    def initialize(opts)
      @workers = Array.new
      @idx = 0
      opts[:worker].times {
        @workers << Worker.new
      }
    end

    def start
      @workers.each { |worker|
        worker.start
      }
    end

    def stop
      @workers.each { |worker|
        worker.stop
      }
    end

    def worker
      @workers[(@idx += 1) == @workers.size ? @idx = 0 : @idx]
    end
  end
end