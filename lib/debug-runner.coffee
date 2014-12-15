spawn = require('child_process').spawn
Q = require('q')
debug = require('debug')('atom-debugger:debug-runner')
DebugServer = require("node-inspector/lib/debug-server").DebugServer
findPort = require('./util').findPort

module.exports =
class DebugRunner
  constructor: (@file, config)->
    @config = config ?
      webHost: ''
      saveLiveEdit: false
      preload: true
      hidden: []
      stackTraceLimit: 50
    
    # note: debugPort and webPort are handled in start().
    
  start: ->
    debug('creating debug server')
    @server = new DebugServer()

    # set up a 'finished' promise that resolves when both processes are done.
    @serverClosed = Q.defer()
    @programExited = Q.defer()
    @finished = Q.all([@serverClosed.promise, @programExited.promise])
    
    Q.all([findPort(8080), findPort(5858)])
    .then ([webPort, debugPort])=>
      debug "got debugPort #{debugPort} and webPort #{webPort}"
      @config.webPort = webPort
      @config.debugPort = debugPort
      @server.start @config
      httpServer = @server._httpServer
      httpServer.on 'listening', ->
        debug('debug server open')
        
      httpServer.on "close", =>
        debug('debug server close')
        httpServer.removeAllListeners()
        @server = null
        @serverClosed.resolve()
        @kill()

      @program = spawn("node",
        params = ["--debug-brk=" + @config.debugPort, @file])
      debug('spawned child process', 'node'+params.join '')

      @program.on 'exit', =>
        debug('child process exit')
        @program.removeAllListeners()
        @program = null
        @programExited.resolve()
        @kill()
      
      # return the debug server and the running program from this promise.
      {server: @server, program: @program}

  
  kill: ->
    @program?.kill()
    @server?._httpServer?.close()
    @finished
    
