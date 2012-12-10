Redom Tutorial

  Redom is a distributed object library for Server-WebBrowser communication. This tutorial shows how to create a web application using Redom.

===============
Getting started
===============

- Creating a Redom connection class

  A Redom connection class is where you write the scripts to manipulate the browser-side objects from server. The Redom connection class must be subclass of 'Redom::RedomConnection'. An instance of Redom connection class will be created when the connection between browser and Redom server is established. There are four methods in 'Redom::RedomConnection' that can be overridden to tell Redom what to do.

  on_open()       - Called when the connection is established.
  on_error(err)   - Called when an browser-side error occurs.
  on_message(msg) - Called when an message is received from browser.(not implemented)
  on_close()      - Called when the connection is shutdown.(not implemented)

  Here is an example:
#
  class MyConnection < Redom::Connection
    def on_open
      window.alert "Hello world!"
    end
    def on_error(error)
      p error
    end
  end
#

- Starting Redom server

  After a Redom connection class is defined, you can start Redom server using 'Redom::start(klass)' method. Your Redom connection class must be passed as the argument.
#
  Redom.start(MyConnection, {:host => 127.0.0.1, :port => 8080})
#

- Adding Redom library to HTML

  Add Redom JavaScript library 'Redom.js' in your HTML. And call 'Redom.start(host)' to connect to a Redom server.
#
  <script type="text/javascript" src="Redom.js"></script>
  <script type="text/javascript">
    window.onload = function() {
      Redom.start("ws://127.0.0.1:8080");
    }
  </script>
#

- Stopping Redom server

  Use 'Redom.stop' to stop a Redom server.
#
  Redom.stop
#

========
API Docs
========

* Module: Redom

  - Redom.start(opts = {})
    
    Start Redom server.

    Parameters:
      opts (Hash) - Options. Default values are as below:
        :worker    => 5   - Number of worker threads.
        :buff_size => 200 - Messages stored before synchronization with browser.

  - Redom.stop

    Stop Redom server.
  

* Class: Redom::Connection

  - sync(conn = nil)

    Parameters:
      conn - The Redom::Connection that should synchronize with browser. If nil, current connection will do synchronization.

    Synchronize with browser immediately.
    
  - connections

    Return all Redom connection instances in an array that the Redom server is holding currently.

    Returns:
      (Array) - An Redom::Connections instances array that contains all Redom::Connection instances the Redom server is holding currently.

    Examples:
      connections.each { |conn|
        conn.do_something
        sync conn
      }

  - window, document

    A reference for browser-side object 'window' and 'document'.

   Returns:
     (Redom::Proxy) - A Redom::Proxy that references to browser-side object 'window' and 'document'.

   Examples:
     window.alert "Hello world."

* Class: Redom:Proxy

  - sync

    Synchronize with browser immediately and return the true value of the referenced object.

    Returns:
      (Object) - Primitive type if the referenced object is primitive, otherwise the Redom::Proxy itself.

    Examples:
      value = document.getElementById("text").value.sync

=====
Hints
=====

- Define a event handler as 'object.event_name = :event_handler_name'
  Examples:
    def button_click_handler(event)
      button = event.srcElement
    end
    document.getElementById("button").onclick = :button_click_handler



