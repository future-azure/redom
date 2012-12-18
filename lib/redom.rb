require 'fiber'
require 'json'
require 'logger'
require 'thread'

$LOAD_PATH << File.dirname(__FILE__) unless $LOAD_PATH.include?(File.dirname(__FILE__))
%w[
  utils connection dispatcher proxy task worker thread_pool runtime version parser
].each { |file|
  require "redom/#{file}"
}

module Redom
  DEFAULT_OPTIONS = {
    :log => STDOUT,
    :log_level => 'error',
    :worker => 5,
    :buff_size => 200
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

  class << self
    # Start Redom dispatcher
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
      Utils.dispatcher = @@dispatcher = Dispatcher.new(opts)
    end

    def stop
      @@dispatcher.stop
    end

    def on_open(ws)
      @@dispatcher.on_open(ws)
    end

    def on_message(ws, msg)
      @@dispatcher.on_message(ws, msg)
    end

    def on_close(ws)
      @@dispatcher.on_close(ws)
    end

    def on_error(ws, err)
      @@dispatcher.on_error(ws, err)
    end

    def parse(str, file='(file)')
      Parser.new.parse str, file
    end
  end
end
