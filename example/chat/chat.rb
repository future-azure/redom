class ChatConnection
  include Redom::Connection

  def j(arg)
    jQuery(arg)
  end

  def receive_chat_msg(event)
    nickname = j("#nickname").attr('value')
    message = j("#message").attr('value')
    j("#message").attr('value', '').focus
    sync{}
    connections.each { |conn|
      conn.send_chat_msg("#{escape(nickname)}: #{escape(message)}")
      sync(conn){}
    }
  end

  def send_chat_msg(message)
    j("#chats").prepend j("<div>[#{Time.now.strftime('%H:%M:%S')}] #{message}</div>")
  end

  def on_open
    j("#status")[0].innerHTML = ''
    j("#btn")[0].onclick = :receive_chat_msg
  end

  def on_error(error)
    p error
  end

  def on_close
    puts 'closed'
  end

  def escape(str)
    str.gsub!('&', '&amp;')
    str.gsub!('<', '&lt')
    str.gsub!('>', '&gt;')
    str
  end
end
