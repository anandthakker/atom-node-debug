
spawn = require('child_process').spawn
Q = require('q')
debug = require('debug')('atom-debugger:debug-runner')
DebugServer = require("node-inspector/lib/debug-server").DebugServer
nodeInspectorConfig = require("node-inspector/lib/config")

module.exports =
class DebugRunner
  constructor: (@file, config)->
    @config = config || nodeInspectorConfig
    
  start: ->
    debug('creating debug server')
    @server = new DebugServer()
    @serverClosed = Q.defer()
    @server.start @config
    httpServer = @server._httpServer
    httpServer.on "close", =>
      debug('debug server close')
      httpServer.removeAllListeners()
      @server = null
      @serverClosed.resolve()
      @kill()

    @program = spawn("node",
      params = ["--debug-brk=" + @config.debugPort, @file])
    debug('spawned child process', 'node'+params.join '')

    @programExited = Q.defer()
    @program.on 'exit', =>
      debug('child process exit')
      @program.removeAllListeners()
      @program = null
      @programExited.resolve()
      @kill()
    
    # set a promise that resolves when both processes are done.
    @finished = Q.all([@serverClosed.promise, @programExited.promise])

  
  kill: ->
    @program?.kill()
    @server?._httpServer?.close()
    @finished
    
