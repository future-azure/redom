require 'socky/server'
require 'redom'
require './chat/chat'
require './othello/othello'

class RedomApp < Rack::WebSocket::Application
  def on_open(env)
    Redom.on_open self
  end

  def on_message(env, msg)
    Redom.on_message self, msg
  end

  def on_close(env)
    Redom.on_close self
  end

  def send(msg)
    send_data msg
  end
end

Redom.start

map '/websocket' do
  run RedomApp.new
end

map '/redom.js' do
  run Proc.new {|env| [200, {"Content-Type" => "text/javascript"}, [Redom.runtime]]}
end

run Rack::Directory.new(File.expand_path('.'))
