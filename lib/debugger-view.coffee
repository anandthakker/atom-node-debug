debug = require('debug')('atom-debugger')

spawn = require('child_process').spawn
path = require('path')
url = require('url')

{View, Range, Point} = require 'atom'

DebuggerApi = require('debugger-api')
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
  initialize: (state) ->
    @activePaneItemChanged()
    atom.workspaceView.on 'pane-container:active-pane-item-changed', =>
      @activePaneItemChanged()

    @breakpoints = state?.breakpoints ? []
    atom.workspaceView.addClass('debugger')
    atom.workspaceView.addClass('debugger--show-breakpoints')
    
    @registerCommand 'debugger:toggle-debug-session',
    '.editor', =>@toggleSession()
    @registerCommand 'debugger:step-into',
    '.debugger--paused', => @bug.stepInto()
    @registerCommand 'debugger:step-over',
    '.debugger--paused', => @bug.stepOver()
    @registerCommand 'debugger:step-out',
    '.debugger--paused', => @bug.stepOut()
    @registerCommand 'debugger:continue',
    '.debugger--paused', => @bug.resume()
    @registerCommand 'debugger:toggle-breakpoint',
    '.editor', => @toggleBreakpointAtCurrentLine()
    @registerCommand 'debugger:clear-all-breakpoints',
    '.editor', =>
      @clearAllBreakpoints()
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


  toggleSession: (port) ->
    if @bug?
      return @endSession()

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

  markers: []
  createMarker: (lineNumber, scriptPath)->
    line = @editor.lineTextForBufferRow(lineNumber)
    range = new Range(new Point(lineNumber,0),
                      new Point(lineNumber, line.length-1))

    @markers.push(marker = @editor.markBufferRange(range))
    marker

  updateMarkers: ->
    debug('update markers')
    @destroyAllMarkers()
    editorPath = @editor.getPath()
    return unless editorPath?
    editorPath = path.normalize(editorPath)
    
    # collect up the decorations we'll want by line.
    map = {} #not really a map, but meh.
    for {lineNumber, scriptPath}, index in @getCurrentPauseLocations()
      continue unless scriptPath is editorPath
      map[lineNumber] ?= ['debugger']
      map[lineNumber].push 'debugger-current-pointer'
      if index is 0 then map[lineNumber].push 'debugger-current-pointer--top'
    
    for bp in @getBreakpoints()
      {locations: [{lineNumber, scriptPath}]} = bp
      continue unless scriptPath is editorPath
      map[lineNumber] ?= ['debugger']
      map[lineNumber].push 'debugger-breakpoint'

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
    @childprocess = null
    @bug?.close()
    @bug = null
    @detach()
  
  serialize: ->
    breakpoints: @breakpoints

  destroy: ->
    atom.workspaceView.removeClass('debugger')
    atom.workspaceView.removeClass('debugger--show-breakpoints')
    @localCommandMap = null
    @endSession()
    @destroyAllMarkers()


  ###
  Wire up modelly stuff to viewy stuff
  ###
  startDebugger: (port) ->
    debug('starting debugger', port)
    # the current list of breakpoints is from before this
    # session. hold them for now, hook 'em up once we've paused.
    breaks = @breakpoints
    @breakpoints = []

    @bug = new DebuggerApi({debugPort: port})
    @bug.enable(null, (err, result)->
      debug('enable done', err, result)
      if(err) then console.error err
      else debug('debugger enabled')
    )

    @bug.on('Debugger.resumed', =>
      debug('resumed')
      @clearCurrentPause()
      @updateMarkers()
      atom.workspaceView.removeClass('debugger--paused')
      return
    )
    @bug.on('Debugger.paused', (breakInfo)=>
      debug('paused')
      atom.workspaceView.addClass('debugger--paused')
      @setCurrentPause(breakInfo)
      @openPath loc=@getCurrentPauseLocations()[0], =>
        @status.text("Paused at line #{loc.lineNumber} of #{loc.scriptPath}")
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
    if not @bug?
      @breakpoints.push(bp)  for bp in breakpoints
      return done()
      
    setNext = (breakpoints, done) =>
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
    
    
