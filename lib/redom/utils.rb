module Redom
  module Utils
    @@logger = nil

    def self.logger=(logger)
      @@logger = logger
    end
    
    def self.dispatcher=(dispatcher)
      @@dispatcher = dispatcher
    end

    def _logger
      @@logger
    end
    
    def _dispatcher
      @@dispatcher
    end
  end
end