(function (global, undefined) {

/** ############ **/
var packets = {
    open:     'o'
  , close:    'c'
  , ping:     'p'
  , pong:     'P'
  , message:  'm'
  , upgrade:  'u'
};

for (var i in packets) packets[packets[i]] = i

/**
 * Premade error packet.
 */

var err = { type: 'error', data: 'parser error' }

/**
 * Encodes a packet.
 *
 *     <packet type id> [ `:` <data> ]
 *
 * Example:
 *
 *     5:hello world
 *     3
 *     4
 *
 * @api private
 */

encodePacket = function (packet) {
  var encoded = packets[packet.type]

  // data fragment is optional
  if (undefined !== packet.data) {
    encoded += String(packet.data);
  }

  return '' + encoded;
};

/**
 * Decodes a packet.
 *
 * @return {Object} with `type` and `data` (if any)
 * @api private
 */

decodePacket = function (data) {
  var r = err
  var type = data.charAt(0)
  if (packets[type]) {
    if (data.length > 1) {
      r = { type: packets[type], data: data.substring(1) };
    } else {
      r = { type: packets[type] };
    }
  }
  return r
};

/**
 * Encodes multiple messages (payload).
 * 
 *     <length>:data
 *
 * Example:
 *
 *     11:hello world2:hi
 *
 * @param {Array} packets
 * @api private
 */

encodePayload = function (packets) {
  if (!packets.length) {
    return '0:';
  }

  var encoded = ''
    , message

  for (var i = 0, l = packets.length; i < l; i++) {
    message = encodePacket(packets[i]);
    encoded += message.length + ':' + message;
  }

  return encoded;
};

/*
 * Decodes data when a payload is maybe expected.
 *
 * @param {String} data
 * @return {Array} packets
 * @api public
 */

decodePayload = function (data) {
  if (data == '') {
    // parser error - ignoring payload
    return [err];
  }

  var packets = []
    , length = ''
    , n, msg, packet

  for (var i = 0, l = data.length; i < l; i++) {
    var chr = data[i]

    if (':' != chr) {
      length += chr;
    } else {
      if ('' == length || (length != (n = Number(length)))) {
        // parser error - ignoring payload
        return [err];
      }

      msg = data.substr(i + 1, n);

      if (length != msg.length) {
        // parser error - ignoring payload
        return [err];
      }

      if (msg.length) {
        packet = decodePacket(msg);

        if (err.type == packet.type && err.data == packet.data) {
          // parser error in individual packet - ignoring payload
          return [err];
        }

        packets.push(packet);
      }

      // advance cursor
      i += n;
      length = ''
    }
  }

  if (length != '') {
    // parser error - ignoring payload
    return [err];
  }

  return packets;
};
/** ############ **/


var isIE8 = global.XDomainRequest ? true : false

//
// decode urlencoded string
//

function urldecode(str) {
  var r = {}
  var parts = (str || '').split('&')
  for (var i = 0; i < parts.length; ++i) {
    if (parts[i].indexOf('=') < 0) {
      r[decodeURIComponent(parts[i])] = true
    } else {
      parts[i].replace(/([^=]+)=(.*)/, function (all, key, value) {
        r[decodeURIComponent(key)] = decodeURIComponent(value)
      })
    }
  }
  return r
}

//
// create XMLHttpRequest
//

function createXHR() {
  try { return new XMLHttpRequest(); } catch(e) {}
  try { return new ActiveXObject('MSXML3.XMLHTTP'); } catch(e) {}
  try { return new ActiveXObject('MSXML2.XMLHTTP.3.0'); } catch(e) {}
  try { return new ActiveXObject('Msxml2.XMLHTTP'); } catch(e) {}
  try { return new ActiveXObject('Microsoft.XMLHTTP'); } catch(e) {}
  throw new Error('Could not find XMLHttpRequest or an alternative.');
}

function noop() {}

function request(url, method, data, callback) {
  var req = isIE8 ? new global.XDomainRequest() : createXHR()
  if (isIE8) {
    // TODO: disable caching by appending ?t=nonce
    // TODO: window.onunload -- nullify onload, onerror, ontimeout, onprogress and try/catch abort()
    req.onload = function () {
      callback(null, req.responseText)
    }
    req.onerror = function (ev) {
      callback({ code: req.status, message: req.statusText })
    }
    req.onprogress = noop
    req.open(method, url)
  } else {
    if ('withCredentials' in req) try { req.withCredentials = true } catch (e) {}
    req.open(method, url, true)
    req.onreadystatechange = function () {
      if (req.readyState === 4) try {
        // 1223 is reported by MSIE for status 204: http://vegdave.wordpress.com/2007/11/05/1223-status-code-in-ie/
        if (req.status === 200 || req.status === 204 || req.status === 1223) {
          callback(null, req.responseText)
        } else {
          // pass error
          callback({ code: req.status, message: req.statusText })
        }
      } catch(e) {
        // error in callback
        typeof console !== 'undefined' && typeof console.error !== 'undefined' && console.error('ERROR IN REQUEST', e)
      }
    }
  }
  req.send(data)
  return req
}

//
// WebSocket surrogate
//
// tries to implement http://dev.w3.org/html5/websockets/#websocket
//

function WebSocketXHR(url, protocols) {

  // interface

  this.url = url
  this.readyState = WebSocketXHR.CONNECTING
  this.bufferedAmount = 0
  this.extensions = ''
  this.protocol = ''
  this.binaryType = 'blob'
  this.onopen = null
  this.onclose = null
  this.onerror = null
  this.onmessage = null

  // public methods.
  // N.B. we don't put them into prototype, since we have to hide helpers

  var self = this
  var url = url.replace(/^ws/, 'http')
  var session = {}
  var recv = null
  var send_queue = []
  var flushing = false

  // close the socket

  this.close = function (code, reason) {
    // sanity check
    if (code && !(code === 1000 || (code >= 3000 && code < 5000))) throw 'InvalidStateError'
    if (this.readyState >= WebSocketXHR.CLOSING) return
    // start closing
    this.readyState = WebSocketXHR.CLOSING
    // abort receiver
    recv && recv.abort()
    // finish closing
    disconnect(true, code, reason)
  }

  // send message

  this.send = function (data) {
    // can't send to connecting socket
    if (this.readyState === WebSocketXHR.CONNECTING) throw 'InvalidStateError'
    // can't send to closed socket
    if (this.readyState >= WebSocketXHR.CLOSING) return false
    // POST data
    this.bufferedAmount += 1
    // put message in outgoing buffer
    send_queue.push(data)
    // shedule flushing
    flush()
    return true
  }

  // helpers

  function fire(name, props) {
//console.log('EV', name, props)
    // event handler defined?
    if (typeof self['on' + name] === 'function') {
      // compose event
      var ev = document.createEvent ? document.createEvent('HTMLEvents') : document.createEventObject()
      ev.initEvent ? ev.initEvent(name, false, false) : ev.type = name
      //ev.target = self
      // augment event with user defined props
      if (props) {
        for (var i in props) if (props[i] !== undefined) ev[i] = props[i]
      }
      // invoke event handler
//console.log('EV!', name, ev)
      try { self['on' + name](ev) } catch(e) {}
    }
  }

  // close the socket

  function disconnect(clean, code, reason) {
    self.readyState = WebSocketXHR.CLOSING
    // ...???...
    //
    self.readyState = WebSocketXHR.CLOSED
    // report socket is closed
    setTimeout(function () {
      fire('close', { wasClean: clean, code: code, reason: reason })
    }, 0)
  }

  // receive packets from remote end

  function receiver() {
    if (self.readyState > WebSocketXHR.OPEN) return
    recv = request(url, 'GET', null, function (err, result) {
      if (err) {
        // aborted request?
        if (err.code === 0) {
          // disconnect the socket with wasClean: true if it is open
          disconnect(self.readyState !== WebSocketXHR.OPEN)
        // request errored
        } else {
          // close the socket with wasClean: false
          disconnect(false)
        }
        recv = null
      } else {
        // N.B. we skip empty messages, they are heartbeats
        if (result) {
          var packets = decodePayload(result)
console.log('PA', result, packets)
          for (var i = 0; i < packets.length; ++i) {
            var type = packets[i].type
            var data = packets[i].data
            // message frame
            if (type === 'message') {
              // report incoming message
              //setTimeout(function () {
                fire('message', { data: data, origin: url })
              //}, 0)
            // ping frame
            } else if (type === 'ping') {
              self.send(encodePacket({ type: 'pong', data: packet.data }))
            // open frame
            } else if (type === 'close') {
              // disconnect with wasClean: false
              disconnect(false)
            // open frame
            } else if (type === 'open' && self.readyState === WebSocketXHR.CONNECTING) {
              // data is session
              // parse session as urlencoded
              session = urldecode(data)
              session.interval = parseInt(session.interval, 10) || 0
console.log('SESS', session)
              // setup receiver URL
              url = url + '/' + session.id
              // mark socket as open
              self.readyState = WebSocketXHR.OPEN
              setTimeout(function () {
                fire('open')
              }, 0)
            // error frame, or error decoding frame
            } else if (type === 'error') {
              disconnect()
              /*if (self.readyState !== WebSocketXHR.OPEN) {
                self.readyState = WebSocketXHR.CLOSED
              }*/
            // unknown frame. ignore
            } else {
console.log('UNKNOWN FRAME', packet)
              disconnect()
            }
          }
        }
        // restart receiver
        setTimeout(receiver, session.interval || 0)
      }
    })
  }

  // flush send queue

  function flush() {
//console.log('FLUSH', flushing)
    if (self.readyState !== WebSocketXHR.OPEN || flushing) return
    var nmessages = send_queue.length
    // TODO: limit?
    if (nmessages > 0) {
      // FIXME: should error occur, _send_queue is just missed...
      var data = send_queue.slice(0, nmessages)
      flushing = true
      try {
        request(url, 'POST', 'm' + data, function (err, result) {
          // error
          if (err) {
            // ???
          // OK
          } else {
            // remove `nmessages` first messages
            send_queue.splice(0, nmessages)
            flushing = false
            // reflect bufferedAmount
            self.bufferedAmount -= nmessages
          }
          // restart flusher
          flush()
          //setTimeout(flush, 0)
        })
      } catch(e) {
        flushing = false
      }
    }
  }

  // start receiver
  setTimeout(receiver, 10)

}

//
// states
//

WebSocketXHR.CONNECTING = 0
WebSocketXHR.OPEN = 1
WebSocketXHR.CLOSING = 2
WebSocketXHR.CLOSED = 3

global.WebSocketXHR = WebSocketXHR

})(window)
