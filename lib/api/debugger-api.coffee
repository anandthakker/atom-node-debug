
{EventEmitter} = require('events')

q = require('q')
WebSocket = require('ws')
debug = require('debug')('atom-debugger:api')

Backend = require('./backend').Backend
registerBackendCommands = require('./register-backend-commands')

class DebuggerEventHandler extends EventEmitter
  
  ###
  @param {Array.<DebuggerAgent.CallFrame>} callFrames
  @param {string} reason
  @param {Object=} auxData
  @param {Array.<string>=} breakpointIds
  ###
  paused: (callFrames, reason, auxData, breakpointIds) ->
    @emit 'paused',
      callFrames: callFrames
      reason: reason
      auxData: auxData
      breakpointIds: breakpointIds

  resumed: ->
    @emit 'resumed'

  globalObjectCleared: ->
    @emit 'globalObjectCleared'
  
  
  ###
  @param {DebuggerAgent.ScriptId} scriptId
  @param {string} sourceURL
  @param {number} startLine
  @param {number} startColumn
  @param {number} endLine
  @param {number} endColumn
  @param {boolean=} isContentScript
  @param {string=} sourceMapURL
  @param {boolean=} hasSourceURL
  ###
  scriptParsed: (scriptId, sourceURL, startLine, startColumn, endLine,
  endColumn, isContentScript, sourceMapURL, hasSourceURL) ->
    scriptObj =
      scriptId: scriptId
      sourceURL: sourceURL
      startLine: startLine
      startColumn: startColumn
      endLine: endLine
      endColumn: endColumn
      isContentScript: isContentScript
      sourceMapURL: sourceMapURL
      hasSourceURL: hasSourceURL

    @emit 'scriptParsed',scriptObj
  
  ###
  @param {string} sourceURL
  @param {string} source
  @param {number} startingLine
  @param {number} errorLine
  @param {string} errorMessage
  ###
  scriptFailedToParse: (sourceURL, source, startingLine,
  errorLine, errorMessage) ->
    
    
  ###
  @param {DebuggerAgent.BreakpointId} breakpointId
  @param {DebuggerAgent.Location} location
  ###
  breakpointResolved: (breakpointId, location) ->
    @emit 'breakpointResolved',
      breakpointId: breakpointId
      location: location

module.exports =
class DebuggerApi extends DebuggerEventHandler
  constructor: ()->
    @debugger = {}
    @page = {}
    @console = {}
    @runtime = {}
    @backend = new Backend(
      DebuggerAgent: @debugger
      PageAgent: @page
      ConsoleAgent: @console
      RuntimeAgent: @runtime
    )
    registerBackendCommands(@backend)
    @backend.registerDebuggerDispatcher(this)
    super
      
  connect: (wsUrl)->
    debug('attempt to connect', wsUrl)
    ws = new WebSocket(wsUrl)
    @backend.setWebSocket(ws)
    ws.once 'open', =>
      debug('ws:open')
      @emit 'connect'
    ws.once 'close', =>
      debug('ws:close')
      @emit 'close'
    ws.on 'message', (message, flags)=>
      debug('message', {message, flags})
      @backend.dispatch(message)
  
  close: ->
    debug('close')
    @removeAllListeners()
    @backend.getWebSocket()?.close()
    @backend.getWebSocket()?.removeAllListeners()
    @backend.setWebSocket(null)
    
  
