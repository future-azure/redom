require '../../lib/djs'

class ChatConnection < DJS::Connection
  def j(arg)
    jQuery(arg)
  end

  def receive_chat_msg(event)
    nickname = j("#nickname").attr('value')
    message = j("#message").attr('value')
    j("#message").attr('value', '').focus
    sync
    DJS.connections.send_chat_msg("#{escape(nickname)}: #{escape(message)}")
  end

  def send_chat_msg(message)
    j("#chats").prepend j("<div>[#{Time.now.strftime('%H:%M:%S')}] #{message}</div>")
  end

  def on_open
    j("#status")[0].innerHTML = j("#first")[0].innerHTML.chomp
    j("#btn")[0].onclick = method(:receive_chat_msg)
  end

  def on_error(error)
    p error
  end

  def escape(str)
    str.gsub!('&', '&amp;')
    str.gsub!('<', '&lt')
    str.gsub!('>', '&gt;')
    str
  end
end

DJS.start(ChatConnection, {:host => '127.0.0.1', :port => 8080, :debug => false})