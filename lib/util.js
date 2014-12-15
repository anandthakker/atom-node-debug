
var net = require('net'),
    Q = require('q'),
    debug = require('debug')('atom-debugger:util')

module.exports = {
  findPort: findPort
}

function findPort(portrange) {
  portrange = portrange || 45032;
  
  debug('searching for port starting with '+portrange);
  // https://gist.github.com/mikeal/1840641
  function getPort (cb) {
    var port = portrange
    portrange += 1
    
    debug('trying '+port);
    var server = net.createServer()
    server.listen(port, function (err) {
      server.once('close', function () {
        debug('found '+port);
        cb(null, port)
      })
      server.close()
    })
    server.on('error', function (err) {
      getPort(cb)
    })
  }
  
  return Q.nfcall(getPort);
}
