spawn = require('child_process').spawn
path = require('path')
url = require('url')
fs = require('fs')

{ScrollView, Range, Point} = require 'atom'

q = require 'q'
DebugServer = require("node-inspector/lib/debug-server").DebugServer
nodeInspectorConfig = require("node-inspector/lib/config")
debug = require('debug')('atom-debugger:view')

DebuggerApi = require('./debugger-api')
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
  initialize: (@debugger) ->
    super
    
    @activePaneItemChanged()
    atom.workspaceView.on 'pane-container:active-pane-item-changed', =>
      @activePaneItemChanged()

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

  # Needed for opening in a pane.
  getTitle: -> "Debug"
  getUri: -> 'atom://debugger/'

  ###
  View control logic.
  ###
  activePaneItemChanged: ->
    paneItem = atom.workspace.getActivePaneItem()
    if paneItem?.getBuffer?()?
      @lastEditorPane = atom.workspace.getActivePane()
      previousEditor = @editor
      @editor = paneItem
      @updateMarkers()  unless previousEditor is @editor


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
      @editor = atom.workspace.getActiveEditor()
      file = @editor.getPath()
      
      @debugServer = new DebugServer()
      @debugServer.on "close", => @endSession()
      @debugServer.start nodeInspectorConfig

      @childprocess = spawn("node",
        params = ["--debug-brk=" + nodeInspectorConfig.debugPort, file])
      @childprocess.stderr.once 'data', =>
        @_connect("ws://localhost:#{nodeInspectorConfig.webPort}/ws")
      
      @childprocess.stdout.on 'data', (m)=>@console.append("<div>#{m}</div>")
      @childprocess.stderr.on 'data', (m)=>@console.append("<div>#{m}</div>")

  endSession: ->
    debug('end session')
    @debugger.close()
    @updateMarkers()
    @childprocess?.kill()
    @childprocess = null
    @debugServer?.removeAllListeners()
    @debugServer?.close()
    @debugServer = null
    
    @status.text('Debugger stopped')


  handlePause: (location) ->
    atom.workspaceView.addClass('debugger--paused')
    @openPath location
    .done =>
      @status.text("Paused at line #{location.lineNumber} "+
                   "of #{@scriptPath(location)}")

      @callFrames.empty()
      frameViews = []
      onShow = (active) =>
        frameViews.forEach (frameView) ->
          frameView.hide()  unless frameView is active
          
        # There's a potential for a race condition here, but it seems unlikely
        # and it's not dire anyway.
        @openPath active.model.location
        
        
      for cf in @debugger.getCallFrames()
        frameViews.push (cfView = new CallFrameView(cf, onShow))
        @callFrames.append cfView

      @updateMarkers()
      
  handleResume: ->
    atom.workspaceView.removeClass('debugger--paused')
    @updateMarkers()
    
  handleScript: (scriptObject) ->
    if /^http/.test scriptObject.sourceURL
      @openPath({scriptUrl: scriptObject.sourceURL, lineNumber: 0},
        {changeFocus: false})

  toggleBreakpointAtCurrentLine: ->
    scriptUrl = @editorUrl()
    lineNumber = @editor.getCursorBufferPosition().toArray()[0]
    
    debug('toggling breakpoint for', scriptUrl)
    @debugger.toggleBreakpoint({lineNumber, scriptUrl})
    .done =>
      debug('toggled breakpoint')
      @updateMarkers()
    , (error) -> debug(error)

  openPath: ({scriptUrl, lineNumber}, options={})->
    debug('open script', scriptUrl, lineNumber)
    return q(@editor) if @isActiveScript(scriptUrl)
    
    @lastEditorPane.activate()
    
    path = @scriptPath(scriptUrl)
    if /^https?:/.test path then path = url.format
      protocol: 'atom'
      slashes: true
      hostname: 'debugger'
      pathname: 'open'
      query: {url: path}
    else if /^file/.test path
      path = url.parse(path).pathname
      
    options.initialLine = lineNumber
    atom.workspaceView.open(path, options)
    .then (@editor)->#just save editor.

  #
  # Markers for breakpoints and paused execution
  #
  markers: []
  createMarker: (lineNumber)->
    line = @editor.lineTextForBufferRow(lineNumber)
    range = new Range(new Point(lineNumber,0),
                      new Point(lineNumber, line.length-1))

    @markers.push(marker = @editor.markBufferRange(range))
    marker

  updateMarkers: ->
    debug('update markers')
    @destroyAllMarkers()
    
    # collect up the decorations we'll want by line.
    map = {} #not really a map, but meh.
    for {lineNumber, scriptUrl}, index in @debugger.getCurrentPauseLocations()
      continue unless @isActiveScript(scriptUrl)
      map[lineNumber] ?= ['debugger']
      map[lineNumber].push 'debugger-current-pointer'
      if index is 0 then map[lineNumber].push 'debugger-current-pointer--top'

    breakpoints = @debugger.getBreakpoints()
    debug('breakpoint markers', breakpoints)
    for bp in @debugger.getBreakpoints()
      {locations: [firstLocation]} = bp
      continue unless @isActiveScript(firstLocation)
      map[firstLocation.lineNumber] ?= ['debugger']
      map[firstLocation.lineNumber].push 'debugger-breakpoint'

    # create markers and decorate them with appropriate classes
    for lineNumber,classes of map
      marker = @createMarker(lineNumber)
      for cls in classes
        @editor.decorateMarker marker,
          type: ['gutter', 'line'],
          class: cls

  destroyAllMarkers: ->
    marker.destroy() for marker in @markers
  

  serialize: ->

  destroy: ->
    atom.workspaceView.removeClass('debugger')
    atom.workspaceView.removeClass('debugger--show-breakpoints')
    @localCommandMap = null
    @endSession()
    @destroyAllMarkers()

  
  #
  # Some helper functions
  #
  
  editorUrl: ->
    edPath = @editor?.getPath() ? null
    if(edPath != null)
      url.format(
        protocol: 'file'
        slashes: 'true'
        pathname: edPath
      )
    else
      @editor?.getBuffer()?.getRemoteUri() ? ''

  scriptPath: (urlOrLoc)->
    origUrl = urlOrLoc.scriptUrl ? urlOrLoc
    earl = url.parse(origUrl, true)
    if earl.protocol is 'file://' then earl.pathname
    else origUrl

  isActiveScript: (urlOrLoc)->
    return false unless (editorUrl = @editorUrl())?
    editorUrl is (urlOrLoc.scriptUrl ? urlOrLoc)
    
  
