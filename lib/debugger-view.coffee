debug = require('debug')('atom-debugger:view')
spawn = require('child_process').spawn
path = require('path')
url = require('url')

{View, Range, Point} = require 'atom'

DebugServer = require("node-inspector/lib/debug-server").DebugServer
nodeInspectorConfig = require("node-inspector/lib/config")

DebuggerApi = require('./debugger-api')
CommandButtonView = require('./command-button-view')


module.exports =
class DebuggerView extends View

  @content: ->
    @div class: "tool-panel panel-bottom padded debugger debugger--ui", =>
      @div class: "panel-heading", =>
        @div class: 'btn-toolbar pull-left', =>
          @div class: 'btn-group', =>
            @button 'Detach',
              click: 'endSession'
              class: 'btn'
        @div class: 'btn-toolbar pull-right', =>
          @div class: 'btn-group', =>
            @subview 'continue', new CommandButtonView('continue')
            @subview 'stepOver', new CommandButtonView('step-over')
            @subview 'stepInto', new CommandButtonView('step-into')
            @subview 'stepOut', new CommandButtonView('step-out')
        @div class: 'debugger-status', 'Debugging', outlet: 'status'
      @div class: "panel-body padded debugger-console", outlet: 'console'

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
    @activePaneItemChanged()
    atom.workspaceView.on 'pane-container:active-pane-item-changed', =>
      @activePaneItemChanged()

    atom.workspaceView.addClass('debugger')
    atom.workspaceView.addClass('debugger--show-breakpoints')
    
    @registerCommand 'debugger:toggle-debug-session',
    '.editor', =>@toggleSession()
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


  ###
  View control logic.
  ###
  activePaneItemChanged: ->
    @editor = null
    @destroyAllMarkers()

    #TODO: what about split panes?
    paneItem = atom.workspace.getActivePaneItem()
    if paneItem?.getBuffer?()?
      @editor = paneItem
      @updateMarkers()


  _connect: (wsUrl)->
    @debugger.connect wsUrl,
      onPause = (location)=>
        @openPath location
        .done =>
          # coffeelint: disable=max_line_length
          @status.text("Paused at line #{location.lineNumber} of #{@scriptPath(location)}")
          # coffeelint: enable=max_line_length
          @updateMarkers()
      , onResume = =>
        @updateMarkers()
      , openScript = (loc)=>@openPath(loc) # TEMPORARY TODO


  toggleSession: (wsUrl) ->
    if @debugger.isActive
      debug('end session')
      @endSession()
      return

    debug('start session', wsUrl)
    atom.workspaceView.prependToBottom(this)

    if wsUrl?
      if /^[0-9]+$/.test(wsUrl+'')
        wsUrl = "ws://localhost:#{wsUrl}/ws"
      @_connect(wsUrl)
    else
      @editor = atom.workspace.getActiveEditor()
      file = @editor.getPath()
      
      @debugServer = new DebugServer()
      @debugServer.on "close", =>
        @endSession()
      @debugServer.start nodeInspectorConfig

      @childprocess = spawn(
        "node",
        params = ["--debug-brk=" + nodeInspectorConfig.debugPort, file]
      )
      @childprocess.stderr.once 'data', =>
        @_connect("ws://localhost:#{nodeInspectorConfig.webPort}/ws")
      
      @childprocess.stdout.on 'data', (data)=>
        @console.append("""
        <div>
        #{data}
        </div>
        """)
        debug('child process stdout',data)
      @childprocess.stderr.on 'data', (data)=>
        @console.append("""
        <div>
        #{data}
        </div>
        """)
        debug('child process stderr',data)


  endSession: ->
    @debugger.close()
    @updateMarkers()
    @childprocess?.kill()
    @childprocess = null
    @debugServer?.removeAllListeners()
    @debugServer?.close()
    @debugServer = null

    @detach()


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
    for {lineNumber, scriptId}, index in @debugger.getCurrentPauseLocations()
      continue unless @isActiveScript(scriptId)
      map[lineNumber] ?= ['debugger']
      map[lineNumber].push 'debugger-current-pointer'
      if index is 0 then map[lineNumber].push 'debugger-current-pointer--top'

    breakpoints = @debugger.getBreakpoints()
    debug('breakpoint markers', breakpoints)
    for bp in @debugger.getBreakpoints()
      {locations: [{lineNumber, scriptId}]} = bp
      continue unless @isActiveScript(scriptId)
      map[lineNumber] ?= ['debugger']
      map[lineNumber].push 'debugger-breakpoint'

    # create markers and decorate them with appropriate classes
    for lineNumber,classes of map
      marker = @createMarker(lineNumber)
      for cls in classes
        @editor.decorateMarker marker,
          type: ['gutter', 'line'],
          class: cls

  destroyAllMarkers: ->
    marker.destroy() for marker in @markers
  
  toggleBreakpointAtCurrentLine: ->
    scriptUrl = @editor.getPath() ? @editor.getBuffer().getRemoteUri()
    return unless scriptUrl?
    @debugger.toggleBreakpoint(
      lineNumber: @editor.getCursorBufferPosition().toArray()[0]
      scriptId: @debugger.getScriptIdForUrl(scriptUrl)
    ).then =>
      debug('toggled breakpoint')
      @updateMarkers()
      # TODO: breakpoint list

  openPath: ({scriptId, lineNumber})->
    debug('open script', scriptId, lineNumber)
    done() if @isActiveScript(scriptId)
    
    path = @scriptPath(scriptId)
    debug(path)
    if /https?:/.test path then path = url.format
      protocol: 'atom'
      slashes: true
      hostname: 'debugger'
      pathname: 'open'
      query:
        url: path
      
    atom.workspaceView.open(path,initialLine: lineNumber)
    .then (@editor)->#just save editor.
  
  serialize: ->

  destroy: ->
    atom.workspaceView.removeClass('debugger')
    atom.workspaceView.removeClass('debugger--show-breakpoints')
    @localCommandMap = null
    @endSession()
    @destroyAllMarkers()
  
  # Private util functions

  scriptUrl: (scriptIdOrLocation)->
    if typeof scriptIdOrLocation is 'object'
      @scriptUrl(scriptIdOrLocation.scriptId)
    else
      @debugger.getScript(scriptIdOrLocation).sourceURL
  
  scriptPath: (scriptIdOrLocation)->
    origUrl = @scriptUrl(scriptIdOrLocation)
    earl = url.parse(origUrl, true)
    if earl.protocol is 'file://' then earl.pathname
    else origUrl
    
  isActiveScript: (scriptIdOrLocation)->
    editorPath = @editor?.getPath()
    return unless editorPath?
    
    path.normalize(editorPath) is path.normalize(scriptPath(scriptIdOrLocation))
    

    
  
