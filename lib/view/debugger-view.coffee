spawn = require('child_process').spawn
path = require('path')
url = require('url')
fs = require('fs')

{Range, Point} = require 'atom'
{ScrollView} = require 'atom-space-pen-views'

debug = require('debug')('atom-debugger:view')
Q = require('q')

@EditorControls = require('../editor-controls')
DebugRunner = require('../debug-runner')
CommandButtonView = require('./command-button-view')
CallFrameView = require('./call-frame-view')


module.exports =
class DebuggerView extends ScrollView

  @content: ->
    @div class: "pane-item debugger debugger-ui", =>
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
  TODO: the commandregistry is here, so remove this.
  ###
  localCommandMap: {}
  registerCommand: (name, filter, callback) ->
    cb = (rgs...)->
      debug('command', name, rgs...)
      callback(rgs...)
    
    cmd = {}
    cmd[name] = cb
    atom.commands.add 'atom-workspace', cmd
    @localCommandMap[name] = cb
  triggerCommand: (name)->
    @localCommandMap[name]()

  ###
  Wire up view commands to DebuggerApi.
  ###
  initialize: (@debugger, @editorControls) ->
    super
    
    @editorControls.onDidEditorChange(@updateMarkers.bind(this))
    @updateMarkers()

    workspaceView = atom.views.getView(atom.workspace)
    workspaceView.classList.add('debugger')
    workspaceView.classList.add('debugger--show-breakpoints')
    
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
    workspaceView = atom.views.getView(atom.workspace)
    workspaceView.classList.remove('debugger')
    workspaceView.classList.remove('debugger--show-breakpoints')
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
    else @startSession(wsUrl)

  startSession: (wsUrl)->
    debug('start session', wsUrl)

    if wsUrl?
      # if we have a ws:// url (or a port with whic to make one), then use it.
      if /^[0-9]+$/.test(wsUrl+'')
        wsUrl = "ws://localhost:#{wsUrl}/ws"
      @_connect(wsUrl)

    else
      # otherwise, start a node (--debug-brk) child process current file mode.
      debug('debug current file', file)
      file = @editorControls.editorPath()
      @debugRunner = new DebugRunner(file)
      @debugRunner.start()
      @debugRunner.finished.then(=>@endSession())
      @debugRunner.program.stderr.once 'data', =>
        @_connect("ws://localhost:#{@debugRunner.config.webPort}/ws")
      logmessage = (m)=>@console.append("<div>#{m}</div>")
      @debugRunner.program.stdout.on 'data', logmessage
      @debugRunner.program.stderr.on 'data', logmessage

  endSession: ->
    debug('end session')
    @updateMarkers()
    @debugRunner?.kill()
    @status.text('Debugger stopped')
    # return a promise that resolves when we're all cleaned up.
    Q.all([@debugger.close(), @debugRunner?.finished ? Q(true)])

  pauseLocation: null
  handlePause: (location) ->
    debug('paused', location)
    atom.views.getView(atom.workspace).classList.add('debugger--paused')
    
    scriptReady =
    if location.scriptUrl? then Q(location) # resolve immediately.
    else (@waitingForScript = Q.defer()).promise #resolve when script is parsed.
    
    @pauseLocation = location
    scriptReady.then =>
      @editorControls.open(@pauseLocation)
    .done =>
      @callFrames.empty()
      @status.text("Paused at line #{@pauseLocation.lineNumber} "+
                   "of #{@editorControls.editorPath()}")
      return unless @pauseLocation.scriptUrl
      @updateMarkers()

      # Build the call frame views.
      # TODO: this should be moved out into its own View.
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
      
      frameViews[0]?.expand()

      
  handleResume: ->
    @pauseLocation = null
    atom.views.getView(atom.workspace).removeClass('debugger--paused')
    @updateMarkers()
    
  handleScript: (scriptObject) ->
    debug('handle script', scriptObject, @pauseLocation)
    
    if /^http/.test scriptObject.sourceURL
      @editorControls.open(scriptObject.sourceURL, 0, {changeFocus: false})
      
    else if(@pauseLocation?.scriptId is scriptObject.scriptId and
    not @pauseLocation?.scriptUrl?)
      @pauseLocation.scriptUrl = scriptObject.sourceURL
      @waitingForScript?.resolve()
      

  toggleBreakpointAtCurrentLine: ->
    scriptUrl = @editorControls.editorUrl()
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
    return unless line?.length?
    range = new Range(new Point(lineNumber,0),
                      new Point(lineNumber, line.length-1))

    @markers.push(marker = @editorControls.editor.markBufferRange(range))
    marker

  updateMarkers: ->
    @destroyAllMarkers()
    
    editorUrl = @editorControls.editorUrl()
    return unless editorUrl?
    
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

  
