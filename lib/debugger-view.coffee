debug = require('debug')
#debug.enable('node-inspector-api')

spawn = require('child_process').spawn
path = require('path')
url = require('url')

{View, Range, Point} = require 'atom'

DebuggerApi = require('debugger-api')
CommandButtonView = require('./command-button-view')


module.exports =
class DebuggerView extends View

  @content: ->
    @div class: "tool-panel panel-bottom padded atom-node-debug and--ui", =>
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
        @span 'Debugging'
      @div class: "panel-body padded and-console", outlet: 'console'

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
  initialize: (state) ->
    @breakpoints = state?.breakpoints ? []
    atom.workspaceView.addClass('atom-node-debug')
    atom.workspaceView.addClass('and--show-breakpoints')
    
    @registerCommand 'atom-node-debug:toggle-debug-session',
    '.editor', =>@toggleSession()
    @registerCommand 'atom-node-debug:step-into',
    '.atom-node-debug--paused', => @bug.stepInto()
    @registerCommand 'atom-node-debug:step-over',
    '.atom-node-debug--paused', => @bug.stepOver()
    @registerCommand 'atom-node-debug:step-out',
    '.atom-node-debug--paused', => @bug.stepOut()
    @registerCommand 'atom-node-debug:continue',
    '.atom-node-debug--paused', => @bug.resume()
    @registerCommand 'atom-node-debug:toggle-breakpoint',
    '.editor', => @toggleBreakpointAtCurrentLine()
    @registerCommand 'atom-node-debug:clear-all-breakpoints',
    '.editor', =>
      @clearAllBreakpoints()
      @updateMarkers()

    btn.commandsReady() for btn in [@continue,@stepOver,@stepOut,@stepInto]


  ###
  View control logic.
  ###
  toggleSession: (port) ->
    if @bug?
      return endSession()

    @activePaneItemChanged()
    atom.workspaceView.on 'pane-container:active-pane-item-changed', =>
      @activePaneItemChanged()
    atom.workspaceView.prependToBottom(this)

    if port?
      @startDebugger(port)
    else
      @editor = atom.workspace.getActiveEditor()
      file = @editor.getPath()
      port = 5858 #umm... actually look for one?
      @childprocess = spawn("node",
        params=["--debug-brk=" + port,file ])
      @childprocess.stderr.once 'data', => @startDebugger(port)

      cmdstr = 'node' + params.join ' '
      @childprocess.stderr.on 'data', (data) =>
        @console.append "<div>#{data}</div>"
      @childprocess.stdout.on 'data', (data) =>
        @console.append "<div>#{data}</div>"

  activePaneItemChanged: ->
    return unless @bug?

    @editor = null
    @destroyAllMarkers()

    #TODO: what about split panes?
    paneItem = atom.workspace.getActivePaneItem()
    if paneItem?.getBuffer?()?
      @editor = paneItem
      @updateMarkers()


  markers: []
  createMarker: (lineNumber, scriptPath)->
    line = @editor.lineTextForBufferRow(lineNumber)
    range = new Range(new Point(lineNumber,0),
                      new Point(lineNumber, line.length-1))

    @markers.push(marker = @editor.markBufferRange(range))
    marker

  updateMarkers: ->
    @destroyAllMarkers()
    editorPath = @editor.getPath()
    return unless editorPath?
    editorPath = path.normalize(editorPath)
    
    # collect up the decorations we'll want by line.
    map = {} #not really a map, but meh.
    for {lineNumber, scriptPath}, index in @getCurrentPauseLocations()
      continue unless scriptPath is editorPath
      map[lineNumber] ?= ['atom-node-debug']
      map[lineNumber].push 'and-current-pointer'
      if index is 0 then map[lineNumber].push 'and-current-pointer--top'
    
    for bp in @getBreakpoints()
      {locations: [{lineNumber, scriptPath}]} = bp
      continue unless scriptPath is editorPath
      map[lineNumber] ?= ['atom-node-debug']
      map[lineNumber].push 'and-breakpoint'

    # create markers and decorate them with appropriate classes
    for lineNumber,classes of map
      marker = @createMarker(lineNumber, editorPath)
      for cls in classes
        @editor.decorateMarker marker,
          type: ['gutter', 'line'],
          class: cls


  destroyAllMarkers: ->
    marker.destroy() for marker in @markers

  
  toggleBreakpointAtCurrentLine: ->
    @toggleBreakpoint(
      lineNumber: @editor.getCursorBufferPosition().toArray()[0]
      scriptPath: @editor.getPath()
    , =>
      @updateMarkers()
      # TODO: breakpoint list
    )

  openPath: ({scriptPath, lineNumber}, done)->
    done() if path.normalize(scriptPath) is path.normalize(@editor.getPath())
    atom.workspaceView.open(scriptPath).done ->
      if editorView = atom.workspaceView.getActiveView()
        position = new Point(lineNumber)
        editorView.scrollToBufferPosition(position, center: true)
        editorView.editor.setCursorBufferPosition(position)
        editorView.editor.moveCursorToFirstCharacterOfLine()
        @editor = atom.workspace.getActiveEditor()
      done()

  endSession: ->
    @clearCurrentPause()
    @updateMarkers()
    @childprocess?.kill()
    @bug?.close() # TODO: unregister handlers orelse memory leak!
    @detach()
  
  serialize: ->
    breakpoints: @breakpoints

  destroy: ->
    atom.workspaceView.removeClass('atom-node-debug')
    atom.workspaceView.removeClass('and--show-breakpoints')
    @localCommandMap = null
    @endSession()
    @destroyAllMarkers()


  ###
  Wire up modelly stuff to viewy stuff
  ###
  startDebugger: (port) ->
    # the current list of breakpoints is from before this
    # session. hold them for now, hook 'em up once we've paused.
    breaks = @breakpoints
    @breakpoints = []

    @bug = new DebuggerApi({debugPort: port})
    @bug.enable()

    @bug.on('Debugger.resumed', =>
      @clearCurrentPause()
      @updateMarkers()
      atom.workspaceView.removeClass('and--paused')
      return
    )
    @bug.on('Debugger.paused', (breakInfo)=>
      atom.workspaceView.addClass('and--paused')
      @setCurrentPause(breakInfo)
      @openPath @getCurrentPauseLocations()[0], =>
        console.log 'paused, cached breaks:',breaks
        if breaks?.length > 0
          @setBreakpoints(breaks, => @updateMarkers())
          breaks = null
        else
          @updateMarkers()
      return
    )


  ###
  DebuggerApi accessor functions.  Everything below this point should be
  ignorant of the View.
  
  TODO: extract into a separate model class, so that this view can
        be reused for other debuggers!
        Uhh... it was late when I wrote that.  Actually want to say:
        extract this into the DebuggerApi itself?
  ###

  ###
  Breakpoints
  ###
  # array of {breakpointId:id, locations:array of {scriptPath, lineNumber}}
  breakpoints: []
  setBreakpoints: (breakpoints, done) ->
    setNext = (breakpoints, done) =>
      console.log 'setting', breakpoints
      return done?() if not breakpoints? or breakpoints.length is 0
      [{breakpointId,locations},tail...] = breakpoints
      [{lineNumber, scriptPath},blah...] = locations
      bp =
        url: url.format
          protocol: 'file'
          pathname: scriptPath
          slashes: true
        lineNumber: lineNumber
      @bug.setBreakpointByUrl(bp, (err, result)=>
        {breakpointId, locations} = result ? {}
        if (err?)
          console.error(err)
        else if not locations?[0]?
          console.error("Couldn't set breakpoint.")
        else
          @breakpoints.push(
            breakpointId: breakpointId
            locations: locations.map (loc)=>@debuggerToAtomLocation(loc)
          )
        setNext(tail, done)
      )
    setNext(breakpoints, done)
    
  setBreakpoint: (location, done)->
    @setBreakpoints([{breakpointId: null, locations: [location]}], done)
    
  removeBreakpoint: (id)->
    @bug.removeBreakpoint({breakpointId: id})
    @breakpoints = @breakpoints.filter ({breakpointId})->breakpointId isnt id
  toggleBreakpoint: ({scriptPath, lineNumber}, done)->
    toRemove = @breakpoints.filter (bp)->
      (scriptPath is bp.locations[0].scriptPath and
      lineNumber is bp.locations[0].lineNumber)
    if toRemove.length > 0
      @removeBreakpoint(bp.breakpointId)  for bp in toRemove
      done()
    else
      @setBreakpoint({scriptPath, lineNumber}, done)

  getBreakpoints: -> [].concat @breakpoints
  clearAllBreakpoints: ->
    @breakpoints = []
  
  
  ###
  Current (paused) point in execution.
  ###
  currentPause: null
  getCurrentPauseLocations: ->
    (@currentPause?.callFrames ? []).map ({location})=>
      @debuggerToAtomLocation(location)
  
  ###* @return {scriptPath, lineNumber} of current pause. ###
  setCurrentPause: (@currentPause)->
    @debuggerToAtomLocation(@currentPause.callFrames[0].location)
  clearCurrentPause: ->
    @currentPause = null

  ###* @return array of {scriptPath, lineNumber} ###
  debuggerToAtomLocation: ({lineNumber, scriptId}) ->
    scriptPath: path.normalize(@bug.scripts.findScriptByID(scriptId).v8name)
    lineNumber: lineNumber
    
    
