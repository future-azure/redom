(function() {
  var
  TYPE_UNDEFINED = 0,
  TYPE_PROXY     = 1,
  TYPE_ARRAY     = 2,
  TYPE_ERROR     = 3,
  TYPE_METHOD    = 4

  REQ_HANDSHAKE         = 0,
  REQ_METHOD_INVOCATION = 1,
  REQ_PROXY_RESULT      = 2,

  P_INFO_OID  = 0,
  P_INFO_RCVR = 1,
  P_INFO_NAME = 2,
  P_INFO_ARGS = 3;

  if (window.Opal) {
    Object.prototype.$djsCall = function(name) {
        if (name == '') {
          return (function(obj) {
            return function(key) {
              return obj[key];
             };
        })(this);
      }
  
      if (name == '$method') {
        return function(methodName) {
          if (Opal.top['$' + methodName]) {
            return Opal.top['$' + methodName];
          } else {
            return function(e) {
              window.djs.invoke(methodName, [e]);
            };
          }
        };
      }
  
      if (Opal.top[name]) {
        if (typeof Opal.top[name] == 'function') {
          return function() {
            return Opal.top[name].apply(Opal.top, arguments);
          };
        } else {
          return function() {
            return Opal.top[name];
          };
        }
      }
      if (name[0] == "$" && this[name] == null) {
        name = name.substring(1);
      };
      
      if (this[name] != null) {
        if (typeof this[name] == 'function') {
          return (function(obj) {
            return function() {
              return obj[name].apply(obj, arguments);
            };
          })(this);
        } else {
          return (function(obj) {
            return function() {
              return obj[name];
            };
          })(this);
        }
      } else if (window[name]) {
        if (typeof window[name] == 'function') {
          return function() {
            return window[name].apply(window, arguments);
          };
        } else {
          return function() {
            return window[name];
          };
        }
      }
  
      return function() {
        return null;
      };
    };
    Object.prototype.$djsAssign = function(name) {
      return (function(obj) {
        return function(value) {
          return obj[name] = value;
        };
      })(this);
    };
    Opal.top.$window = window;
    Opal.top.$document = window.document;
    Opal.top.$navigator = window.navigator;
    Opal.top.$location = window.location;
  }

  var Redom = function(server) {
    var ws = new WebSocket(server),
      refs = {
        seq: 0,
        hash: {},
        put: function() {
          var key;
          if (arguments.length == 2) {
            key = arguments[0];
            this.hash[key] = arguments[1];
          } else if (arguments.length == 1) {
            key = "R" + (++this.seq);
            this.hash[key] = arguments[0];
          } else {
            console.log("ERROR: wrong number of arguments!");
          }
          return key;
        },
        get: function(key) {
          return this.hash[key];
        }
      },
      tasks = [];

    // Initialize refs
    refs.put("window", window);
    refs.put("document", document);
    refs.put("history", history);
    refs.put("navigator", navigator);
    refs.put("location", location);

    // Initialize WebSocket event handlers
    function open(connectionClassName) {
      ws.onopen = function() {
        ws.send(serialize([REQ_HANDSHAKE, connectionClassName]));
        console.log("WebSocket opened.");
      };
      ws.onclose = function() {
        console.log("WebSocket closed.");
      };
      ws.onerror = function(error) {
        console.log(error);
      };
      ws.onmessage = function(event) {
        var data = unserialize(event.data);
        var tid = data[0];
        var proxies = data[1];
        var queue = tasks[tid];
        if (!queue) {
          queue = [];
          tasks[tid] = queue;
        }
        for (var i = 0; i < proxies.length; i++) {
          queue.push(proxies[i]);
        }
        try {
          process(tid);
        } catch (e) {
          console.log(e);
        }
      };
    };

    // Close this WebSocket connection
    function close() {
      ws.close();
    }

    // Serialize JavaScript object into message
    function serialize(data) {
      return JSON.stringify(data);
    };
    // Unserialize message into JavaScript object
    function unserialize(msg) {
      return JSON.parse(msg);
    };

    // Restore arguments
    function restore(args) {
      if (args instanceof Array) {
        switch(args[0]) {
        case TYPE_ARRAY:
          for (var i = 0; i < args[1].length; i++) {
            args[1][i] = restore(args[1][i]);
          }
          return args[1];
          break;
        case TYPE_PROXY:
          return refs.get(args[1]);
          break;
        case TYPE_METHOD:
          return (function(name) {
            if (window[name] && typeof(window[name]) == 'function') {
              return function() {
                window[name];
              };
            } else {
              return function() {
                var type, args = [];
                for (var i = 0; i < arguments.length; i++) {
                  switch(type = typeOf(arguments[i])) {
                    case null:
                      args.push(arguments[i]);
                      break;
                    case TYPE_PROXY:
                    case TYPE_ARRAY:
                      args.push([type, refs.put(arguments[i])]);
                      break;
                  }
                }
                ws.send(serialize([REQ_METHOD_INVOCATION, name, args]));
              }
            }
          })(args[1]);
          break;
        }
      } else {
        return args;
      }
    };

    // Evaluation proxies from server
    function process(tid) {
      var proxy, oid, name, args, result, type,
        rsps = [],
        queue = tasks[tid];
      while (proxy = queue.shift()) {
        oid = proxy[P_INFO_OID];
        rcvr = refs.get(proxy[P_INFO_RCVR]);
        name = proxy[P_INFO_NAME];
        args = restore(proxy[P_INFO_ARGS]);

        if (rcvr) {
          result = execute(rcvr, name, args);
          if (result == undefined) {
            rsps.push([oid, [TYPE_UNDEFINED]]);
            ws.send(serialize([REQ_PROXY_RESULT, tid, rsps]));
            return;
          } else {
            refs.put(oid, result);
            switch (type = typeOf(result)) {
              case null:
                rsps.push([oid, result]);
                break;
              case TYPE_PROXY:
              case TYPE_ARRAY:
                rsps.push([oid, [type]]);
                break;
            };
          }
        } else {
          rsps.push([oid, TYPE_ERROR, "no such object. ID='" + proxy[P_INFO_RCVR] + "'."]);
          ws.send(serialize([REQ_PROXY_RESULT, tid, rsps]));
          return;
        }
      }
      ws.send(serialize([REQ_PROXY_RESULT, tid, rsps]));
    };

    // Type of object
    function typeOf(obj) {
      switch(typeof obj) {
        case "string":
        case "number":
        case "boolean":
        case "undefined":
          return null;
        case "object":
          if (obj == null) {
            return null;
          } else if (obj instanceof Array) {
            return TYPE_ARRAY;
          } else {
            return TYPE_PROXY;
          }
        case "function":
          return TYPE_METHOD;
      }
      return TYPE_UNDEFINED;
    }

    // Method invocation
    function execute(rcvr, name, args) {
      var result;
      if (name.match(/^(.+)=$/)) {
        name = RegExp.$1;
        if (name == "[]") {
          result = rcvr[args[0]] = args[1];
        } else {
          result = rcvr[name] = args[0];
        }
      } else {
        if (name == "[]") {
          result = rcvr[args[0]];
        } else {
          result = rcvr[name];
          if (typeof result == "function") {
            result = result.apply(rcvr, args);
          }
        }
      }
      return result;
    };

    return {
      getServer: function() {
        return server;
      },

      open: function(connectionClassName) {
        open(connectionClassName);
      },

      close: function() {
        close();
      }
    };
  };

  window.Redom = Redom;
})();
