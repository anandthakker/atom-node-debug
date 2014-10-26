spawn = require('child_process').spawn
path = require('path')
url = require('url')
fs = require('fs')

{ScrollView, Range, Point} = require 'atom'

Q = require('q')

debug = require('debug')('atom-debugger:view')
DebugServer = require("node-inspector/lib/debug-server").DebugServer
nodeInspectorConfig = require("node-inspector/lib/config")

@EditorControls = require('../editor-controls')
CommandButtonView = require('./command-button-view')
CallFrameView = require('./call-frame-view')


module.exports =
class DebuggerView extends ScrollView

  @content: ->
    @div class: "pane-item", =>
      @div class: "debugger debugger-ui", =>
        @div class: "panel-heading", =>
          @div class: 'btn-group debugger-detach', =>
            @button 'Detach',
              click: 'endSession'
              class: 'btn'
          @div class: 'debugger-status', outlet: 'status', 'Debugging'
          @div class: 'btn-toolbar debugger-control-flow', =>
            @div class: 'btn-group', =>
              @subview 'continue', new CommandButtonView('continue')
              @subview 'stepOver', new CommandButtonView('step-over')
              @subview 'stepInto', new CommandButtonView('step-into')
              @subview 'stepOut', new CommandButtonView('step-out')
        @div class: "panel-body", =>
          @div class: 'tool-panel bordered debugger-console', =>
            @div class: 'panel-heading', 'Console'
            @div class: 'panel-body', outlet: 'console'
          @div class: 'debugger-call-frames', outlet: 'callFrames'

  ###
  To make up for the lack of a good central command manager
  (which seems to be coming soon, based on master branch of atom...)
  ###
  localCommandMap: {}
  registerCommand: (name, filter, callback) ->
    atom.workspaceView.command name, callback
    @localCommandMap[name] = callback
  triggerCommand: (name)->
    @localCommandMap[name]()

  ###
  Wire up view commands to DebuggerApi.
  ###
  initialize: (@debugger, @editorControls) ->
    super
    
    @editorControls.onDidEditorChange(@updateMarkers.bind(this))
    @updateMarkers()

    atom.workspaceView.addClass('debugger')
    atom.workspaceView.addClass('debugger--show-breakpoints')
    
    @registerCommand 'debugger:step-into',
    '.debugger--paused', => @debugger.stepInto()
    @registerCommand 'debugger:step-over',
    '.debugger--paused', => @debugger.stepOver()
    @registerCommand 'debugger:step-out',
    '.debugger--paused', => @debugger.stepOut()
    @registerCommand 'debugger:continue',
    '.debugger--paused', => @debugger.resume()
    @registerCommand 'debugger:toggle-breakpoint',
    '.editor', => @toggleBreakpointAtCurrentLine()
    @registerCommand 'debugger:clear-all-breakpoints',
    '.editor', =>
      @debugger.clearAllBreakpoints()
      @updateMarkers()

    btn.commandsReady() for btn in [@continue,@stepOver,@stepOut,@stepInto]

  serialize: ->

  destroy: ->
    atom.workspaceView.removeClass('debugger')
    atom.workspaceView.removeClass('debugger--show-breakpoints')
    @localCommandMap = null
    @endSession()
    @destroyAllMarkers()


  # Needed for opening in a pane.
  getTitle: -> "Debugger"
  getUri: -> 'atom://debugger/'


  ###
  View control logic.
  ###

  _connect: (wsUrl)->
    @debugger.connect wsUrl,
      @handlePause.bind(this),
      @handleResume.bind(this),
      @handleScript.bind(this)

  toggleSession: (wsUrl) ->
    if @debugger.isActive then @endSession()
    else @startSession()

  startSession: (wsUrl)->
    debug('start session', wsUrl)

    if wsUrl?
      # if we have a ws:// url (or a port with whic to make one), then use it.
      if /^[0-9]+$/.test(wsUrl+'')
        wsUrl = "ws://localhost:#{wsUrl}/ws"
      @_connect(wsUrl)

    else
      # otherwise, start a node (--debug-brk) child process current file mode.
      file = @editorControls.editorPath()
      debug('debug current file', file)
      
      debug('creating debug server')
      @debugServer = new DebugServer()
      @debugServerClosed = Q.defer()
      @debugServer.start nodeInspectorConfig
      @debugServer._httpServer.on "close", =>
        debug('debug server close')
        @debugServer._httpServer.removeAllListeners()
        @debugServer = null
        @debugServerClosed.resolve()
        @endSession()

      @childprocess = spawn("node",
        params = ["--debug-brk=" + nodeInspectorConfig.debugPort, file])
      debug('spawned child process', 'node'+params.join '')


      @childprocess.on 'exit', =>
        debug('child process exit')
        @childprocess.removeAllListeners()
        @childprocess = null
        @childprocessClosed.resolve()
        @endSession()

      @childprocess.stderr.once 'data', =>
        @_connect("ws://localhost:#{nodeInspectorConfig.webPort}/ws")
        @childprocessClosed = Q.defer()

      @childprocess.stdout.on 'data', (m)=>@console.append("<div>#{m}</div>")
      @childprocess.stderr.on 'data', (m)=>@console.append("<div>#{m}</div>")

  endSession: ->
    debug('end session')
    @updateMarkers()
    @childprocess?.kill()
    @debugServer?._httpServer?.close()
    
    @status.text('Debugger stopped')

    Q.all([@debugger.close(), @childprocessClosed, @debugServerClosed])

  pauseLocation: null
  handlePause: (location) ->
    debug('paused', location)
    atom.workspaceView.addClass('debugger--paused')
    @editorControls.open(location)
    .done =>
      @pauseLocation = location
      @status.text("Paused at line #{location.lineNumber} "+
                   "of #{@editorControls.editorPath()}")

      @callFrames.empty()
      
      return unless @pauseLocation.scriptUrl
      
      frameViews = []
      onExpand = (active) =>
        frameViews.forEach (frameView) ->
          frameView.collapse()  unless frameView is active
          
        # There's a potential for a race condition here, but it seems unlikely
        # and it's not dire anyway.
        @editorControls.open(active.model.location)
        
        
      for cf in @debugger.getCallFrames()
        frameViews.push (cfView = new CallFrameView(cf, onExpand))
        @callFrames.append cfView
      
      frameViews[0].expand()

      @updateMarkers()
      
  handleResume: ->
    @pauseLocation = null
    atom.workspaceView.removeClass('debugger--paused')
    @updateMarkers()
    
  handleScript: (scriptObject) ->
    if /^http/.test scriptObject.sourceURL
      @editorControls.open(scriptObject.sourceURL, 0, {changeFocus: false})
    else if @pauseLocation? and not @pauseLocation?.scriptUrl?
      @pauseLocation.scriptUrl = scriptObject.sourceURL
      @editorControls.open(location)

  toggleBreakpointAtCurrentLine: ->
    scriptUrl = editorUrl(@editorControls.editor())
    lineNumber = @editorControls.editor.getCursorBufferPosition().toArray()[0]
    
    debug('toggling breakpoint for', scriptUrl)
    @debugger.toggleBreakpoint({lineNumber, scriptUrl})
    .done =>
      debug('toggled breakpoint')
      @updateMarkers()
    , (error) -> debug(error)


  #
  # Markers for breakpoints and paused execution
  #
  markers: []
  createMarker: (lineNumber)->
    lineNumber = parseInt(lineNumber, 10)
    line = @editorControls.editor.lineTextForBufferRow(lineNumber)
    unless line?.length?
      debugger
    range = new Range(new Point(lineNumber,0),
                      new Point(lineNumber, line.length-1))

    @markers.push(marker = @editorControls.editor.markBufferRange(range))
    marker

  updateMarkers: ->
    @destroyAllMarkers()
    
    editorUrl = @editorControls.editorUrl()
    
    # collect up the decorations we'll want by line.
    map = {} #not really a map, but meh.
    for {lineNumber, scriptUrl}, index in @debugger.getCurrentPauseLocations()
      continue unless scriptUrl is editorUrl
      map[lineNumber] ?= ['debugger']
      map[lineNumber].push 'debugger-current-pointer'
      if index is 0 then map[lineNumber].push 'debugger-current-pointer--top'

    breakpoints = @debugger.getBreakpoints()
    for bp in @debugger.getBreakpoints()
      {locations: [firstLocation]} = bp
      continue unless firstLocation?.scriptUrl? and
        firstLocation.scriptUrl is editorUrl
      map[firstLocation.lineNumber] ?= ['debugger']
      map[firstLocation.lineNumber].push 'debugger-breakpoint'

    # create markers and decorate them with appropriate classes
    for lineNumber,classes of map
      marker = @createMarker(lineNumber)
      for cls in classes
        @editorControls.editor.decorateMarker marker,
          type: ['gutter', 'line'],
          class: cls

  destroyAllMarkers: ->
    marker.destroy() for marker in @markers

  
