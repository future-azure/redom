(function() {
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

	var djs = function() {
		djs.prototype = {
			server: "ws://127.0.0.1:8080",
			cid: 0,
			tasks: new Array(),
			refs: new function() {
				this.seq = 0;
				this.refs = new Array();
				this.add = function(key, obj) {
					this.refs[key] = obj;
				};
				this.create = function(obj) {
					var key = "c" + (++this.seq);
					this.refs[key] = obj;
					return key;
				};
				this.get = function(key) {
					return this.refs[key];
				};
			},
			funcs: new Array(),

			init: function() {
				this.refs.add("window", window);
				this.refs.add("document", document);
				this.refs.add("navigator", navigator);
				this.refs.add("location", location);
				return this;
			},

			start: function(server) {
				this.server = server;
				this.ws = new WebSocket(this.server);
				this.ws.onopen = function(djs) {
					return function() {
						djs.onopen.call(djs);
					};
				}(this);
				this.ws.onclose = function(djs) {
					return function() {
						djs.onclose.call(djs);
					};
				}(this);
				this.ws.onmessage = function(djs) {
					return function(event) {
						djs.onmessage.call(djs, event);
					}
				}(this);
				this.ws.onerror = function(djs) {
					return function(error) {
						djs.onerror.call(djs, error);
					}
				}(this);
			},

			close: function() {
				this.ws.close();
			},

			onopen: function() {
				console.log("opend");
			},

			onhandshake: function() {
				console.log("handshaked");
				this.send({
					"cid"  : this.cid,
					"type" : this.constants.ON_HANDSHAKE
				});
			},

			onclose: function() {
				console.log("closed");
			},

			onmessage: function(event) {
				// console.log(event.data);
				var message = this.unserialize(event.data);
				this.cid = message.cid;
				var fid = message.fid;
				var proxies = message.prxs;
				var stack = this.tasks[fid];
				if (!stack) {
					stack = new Array();
					this.tasks[fid] = stack;
				}
				if (proxies) {
					for (var i = 0; i < proxies.length; i++) {
						stack.push(proxies[i]);
					}
				}
				this.process(message.tid, fid);
			},

			onerror: function(error) {
				console.log(error);
			},

			serialize: function(obj) {
				return JSON.stringify(obj);
			},

			unserialize: function(msg) {
				return JSON.parse(msg);
				// var proxies = JSON.parse(msg);
				// if (proxies instanceof Array) {
					// return proxies;
				// } else {
					// return null;
				// }
			},

			process: function(tid, fid) {
				var object, result, proxy, conn, i, args, rsps = new Array();
				var stack = this.tasks[fid];
				while (proxy = stack.shift()) {
					if (proxy.args) {
						proxy.args = this.toArg(proxy.args);
					}
					switch(proxy.type) {
						case this.constants.HANDSHAKE:
							this.cid = proxy.cid;
							this.onhandshake();
							return;
						case this.constants.METHOD_INVOCATION:
							if (object = this.refs.get(proxy.rcvr)) {
								if (!proxy.mlt) {
									proxy.args = [proxy.args];
								}
								for (i = 0; i < proxy.args.length; i++) {
									args = proxy.args[i];
									if (proxy.name == "[]") {
										result = object[args[0]];
									} else if (proxy.name == "[]=") {
										object[args[0]] = args[1];
										result = args[1];
									} else {
										result = object[proxy.name];
										if (typeof result == "undefined") {
											rsps.push({
												"oid" : proxy.oid,
												"type": this.constants.TYPE_UNDEFINED
											});
											this.send({
												"tid" : tid,
												"fid" : fid,
												"cid" : this.cid,
												"type": this.constants.PROXY_RESPONSE,
												"prx" : rsps
											});
											return;
										}
										if (typeof result == "function") {
											result = result.apply(object, args);
										}
									}

									if (this.isPrimitive(result)) {
										rsps.push({
											"oid" : proxy.oid,
											"type": this.constants.TYPE_PRIMITIVE,
											"org" : result
										});
									} else if (result instanceof Array) {
										rsps.push({
											"oid" : proxy.oid,
											"type": this.constants.TYPE_ARRAY,
											"org" : this.toRubyArray(result)
										});
									} else {
										this.refs.add(proxy.oid, result);
										rsps.push({
											"oid" : proxy.oid,
											"type": this.constants.TYPE_OBJECT
										});
									}
								}
							} else {
								console.log("Method Invocation Error: No such object");
							}
							break;
						case this.constants.PROPERTY_ASSIGNMENT:
							if ((object = this.refs.get(proxy.rcvr)) && proxy.args.length > 0) {
								object[proxy.name] = proxy.args[0];
							} else {
								console.log("Property Assignment Error: " + proxy);
							}
							break;
						case this.constants.EVENTHANDLER_DEFINITION:
							if ((object = this.refs.get(proxy.rcvr)) && proxy.args.length > 0) {
								object[proxy.name] = this.createEventHandler(this, proxy.args[0]);
							}
							break;
						case this.constants.ON_RPC:
							this.send({
								"cid" : this.cid,
								"type": this.constants.ON_RPC,
								"rpc" : proxy.rpc,
								"args": proxy.args
							});
							break;
						default:
							console.log("Proxy Type Error: " + proxy.type);
							console.log(proxy);
					}
				}
				this.send({
					"tid" : tid,
					"fid" : fid,
					"cid" : this.cid,
					"type": this.constants.PROXY_RESPONSE,
					"prx" : rsps
				});
			},

			createEventHandler: function(djs, name) {
		        return function(e) {
		            // if (djs.funcs[name]) {
		                // djs.funcs[name](e);
		            if (window.Opal && Opal.top['$' + name]) {
		            	Opal.top['$' + name](e);
		            } else {
		            	djs.invoke(name, [e]);
		            }
		        };
			},

			invoke: function(name, args) {
				var argsInfo = new Array();
				var arg;
				for (var i = 0; i < args.length; i++) {
					arg = args[i];
					if (this.isPrimitive(arg)) {
						argsInfo.push([this.constants.TYPE_PRIMITIVE, arg]);
					} else {
						argsInfo.push([this.constants.TYPE_OBJECT, this.refs.create(arg)]);
					}
				}
				this.send({
					"cid"  : this.cid,
					"type" : this.constants.METHOD_INVOCATION,
					"name" : name,
					"args" : argsInfo
				});
			},

			isPrimitive: function(obj) {
				switch(typeof obj) {
					case "string":
					case "number":
					case "boolean":
					case "undefined":
						return true;
					case "object":
						if (obj == null) {
							return true;
						}
				}
				return false;
			},

			toRubyArray : function(obj) {
				var arr = new Array(obj.length);
				for (var i = 0; i < obj.length; i++) {
					if (this.isPrimitive(obj[i])) {
						arr[i] = {"type" : this.constants.TYPE_PRIMITIVE, "org" : obj[i]};
					} else {
						arr[i] = {"type" : this.constants.TYPE_OBJECT, "org" : this.refs.create(obj[i])};
					}
				}
				return arr;
			},

			toArg: function(arg) {
				var newArg, i;
				switch(arg[0]) {
					case this.constants.TYPE_PRIMITIVE:
						return arg[1];
						break;
					case this.constants.TYPE_ARRAY:
						newArg = new Array();
						for (i = 0; i < arg[1].length; i++) {
							newArg[i] = this.toArg(arg[1][i]);
						}
						return newArg;
						break;
					case this.constants.TYPE_HASH:
						newArg = new Object();
						for (i in arg[1]) {
							newArg[i] = this.toArg(arg[1][i]);
						}
						return newArg;
						break;
					case this.constants.TYPE_OBJECT:
						return this.refs.get(arg[1]);
						break;
					case this.constants.TYPE_FUNCTION:
						if (window.Opal && Opal.top[arg[1]]) {
							return Opal.top[arg[1]];
						}
						if (window[arg[1]]) {
							return window[arg[1]];
						}
						return (function(djs) {
							return function() {
								djs.invoke(arg[1], arguments);
							};
						})(this);
						break;
				}
			},
			
			send: function(obj) {
				this.ws.send(this.serialize(obj));
			}
		};

		djs.prototype.constants = {
			// Proxy type
			HANDSHAKE               : 0,
			METHOD_INVOCATION       : 1,
			PROPERTY_ASSIGNMENT     : 2,
			EVENTHANDLER_DEFINITION : 3,
			EVENTHANDLER_INVOCATION : 4,
			PROXY_RESPONSE          : 5,
			ON_HANDSHAKE            : 6,
			ON_RPC                  : 7,
			// Object type
			TYPE_PRIMITIVE : 1,
			TYPE_OBJECT    : 2,
			TYPE_UNDEFINED : 3,
			TYPE_ERROR     : 4,
			TYPE_ARRAY     : 5,
			TYPE_HASH      : 6,
			TYPE_FUNCTION  : 7
		};

		return djs.prototype.init();
	};

	window.djs = djs();
})();