Redom
=====
Redom is a distributed object based server-centric user-friendly web application framework. Redom enables developers to write all application logics in Ruby at server side easily using both browser-side and server-side libraries. Redom provides distributed objects published by browser in natural Ruby syntax so that developers can access browser-side objects directly.

Redom requires Ruby 1.9 or higher.
 
Getting started
---------------
### Installation ###
#### `$ gem install redom`

### Usage ###
1. __Create a Redom connection class__  
    A Redom connection class is where you write the scripts to manipulate the browser-side objects from server. The Redom connection class must include module **Redom::Connection**. An instance of Redom connection class will be created when the connection between browser and Redom server is established. There are three methods in **Redom::Connection** that can be overridden to tell Redom what to do.  
  * __on_open__ &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;- Called when the connection is established.  
  * __on_close__ &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;- Called when the connection is closed.  
  * __on_error(err)__ - Called when an error occurs.  
&nbsp;  

2. __Access to browser-side objects__  
    Every browser-side object is published as a ditributed object. Therefore, method invocation and property reference of these objects can be done as if they are Ruby objects.  
    Example: document.getElementById('text').value

3. __Start Redom server__  
    Assuming you have created a Redom connection class and saved it into a file `app.rb`, you can start Redom server using command `redom app.rb`.  
    Redom uses WebSocket as the server/browser communication protocol. [EM-WebSocket] is used as the default WebSocket server in Redom.

4. __Connect to Redom server from a web page__  
    Once you have added Redom JavaScript runtime into the web page, you can use `Redom("ws://localhost:8080").open("RedomConnectionClassName")` to connect to a Redom server. The operations written in the specified Redom connection class will be processed.

[EM-WebSocket]:https://github.com/igrigorik/em-websocket

### Example: Hello World! ###
hello.rb

    require 'redom'
    
    class HelloConnection
      inlcude Redom::Connection
      
      def on_open
        alert "Hello World!"
      end
      
      def on_close
        puts "Browser is closed."
      end
    end

hello.html

    <html>
      <head>
        <title>Hello World!</title>
        <script type="text/javascript" src="redom.js"></script>
        <script type="text/javascript">
          window.onload = function() {
            Redom("ws://localhost:8080").open("HelloConnection");
          }
        </script>
      </head>
    </html>

See more examples in `example`

API Docs
--------

#### (Module) Redom

- __Redom.start(opts = {})__
  
  Start Redom server.

  Parameter:
    opts (Hash) - Options. Default values are as below:
      :log       => STDOUT  - Log file
      :log_level => 'error' - Log level. [fatal|error|warn|info|debug]
      :worker    => 5       - Number of worker threads.
      :buff_size => 200     - Size of bluk messages before synchronization with browser.

- __Redom.stop__

  Stop Redom server.

#### (Module) Redom::Connection

- __connections__

  Return all Redom connection instances in an array that the Redom server is holding currently.

  Return:  
    (Array) - An array of Redom::Connection instances

  Example:  

        connections.each { |conn|
          conn.do_something
        }

- __sync{}__

  Synchronize with browser immediately. Notice that a null block is required.

  Return:  
    nil

  Example:  

        a = document.getElementById("a").value
        b = document.getElementById("b").value
        sync{}
        puts a + b

- __sync__

  Return a synchronous method caller of this connection. Any method of this connection can be called through this  method caller. Current process will be blocked until the method invocation is done.

  Return:  
    (Redom::Connection::Sender) - A synchronous method caller
    
  Example:  

        def foo
          sleep 5
          "bar"
        end
        p sync.foo # will print "bar" after 5 seconds

- __async { ... }__

  Evaluate the code inside the block asynchronously which means current process will not be blocked.

  Return:  
    nil
    
  Example:  

        def foo
          sleep 5
          "bar"
        end
        p async {
          p foo
        } # print "nil" immediately and will print "bar" after 5 seconds

- __async__

  Return a asynchronous method caller of this connection. Any method of this connection can be called through this  method caller and current process will not be blocked. The return value of the method invocation can not be retrieved.

  Return:  
    (Redom::Connection::Sender) - A asynchronous method caller

  Example:  

        def foo
          sleep 5
          "bar"
        end
        p async.foo # print "nil" immediately and will print "bar" after 5 seconds

- __window, document__

  A reference for browser-side object 'window' and 'document'.

 Returns:  
   (Redom::Proxy) - A Redom::Proxy that references to browser-side object 'window' and 'document'.

 Examples:  
   `window.alert "Hello world."`
   `alert "Hello World." (window can be omitted)`

- __parse(src)__

  Parse Ruby code into JavaScript code.

  Parameter:  
    src (String) - Ruby code

  Return:  
    (String) - JavaScript code.

  Example:  
    `window.eval parse("alert 'Hello World.'")`

#### (Class) Redom:Proxy

- __sync__

  Synchronize with browser immediately and return the true value of the referenced object.

  Returns:  
    (Object) - Primitive type if the referenced object is primitive, otherwise the Redom::Proxy itself.

  Examples:  
    `value = document.getElementById("text").value.sync`

Hints
-----

#### * Define a event handler as 'object.event_name = :event_handler_name'  
  Examples:  

    def button_click_handler(event)
      button = event.srcElement
    end
    document.getElementById("button").onclick = :button_click_handler

License
----------
The [MIT] License - Copyright &copy; 2012 Yi Hu
[MIT]: http://www.opensource.org/licenses/mit-license.php

Contact
-------
Email: future.azure@gmail.com
