spawn = require('child_process').spawn

_ = require 'underscore-plus'
Q = require 'q'

debug = require('debug')
# debug.enable('atom-debugger:editor-controls,atom-debugger:view')

DebugServer = require("node-inspector/lib/debug-server").DebugServer
nodeInspectorConfig = require("node-inspector/lib/config")

# yuck.
nextDebugPort = 5001
nextWebPort = 9000

exports.nodeDebug = nodeDebug = (srcForDebug) ->
  port = nextDebugPort++
  console.log "spawning: node --debug-brk=#{port} #{srcForDebug}"
  childprocess = spawn('node', ['--debug-brk='+port, srcForDebug])

  deferred = Q.defer()
  # node debug message shows up on stderr... wait for that before
  # resolving the promise.
  childprocess.stderr.once 'data', -> deferred.resolve({childprocess, port})
  childprocess.on 'error', deferred.reject
  childprocess.on 'exit', deferred.reject

  deferred.promise.finally ->
    childprocess.removeAllListeners()
    Q.delay(10000).then -> childprocess.kill()

  deferred.promise

exports.nodeInspector = nodeInspector = (srcForDebug)->
  nodeDebug(srcForDebug).then ({childprocess, port})->
    webPort = nextWebPort++
    debugServer = new DebugServer()
    config =
      webPort: webPort
      debugPort: port

    # # hack the node-inspector server to remember the websocket port
    # # (bug where it's using the first request's `upgradeReq.url` for the port,
    # # but said url ends up being relative for some reason).
    # debugServer._getDebuggerPort = ->
    #   port
    #
    debugServer.start config

    deferred = Q.defer()
    debugServer.on 'listening', ->
      deferred.resolve(
        url: 'ws://localhost:'+webPort
        server: debugServer
        child: childprocess
      )
    debugServer.on 'error', deferred.reject

    deferred.promise.finally ->
      Q.delay(10000).then -> debugServer.close()
      
    deferred.promise
