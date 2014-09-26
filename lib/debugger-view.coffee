debug = require('debug')
#debug.enable('node-inspector-api')

_ = require 'underscore-plus'
spawn = require('child_process').spawn
path = require('path')
url = require('url')

{View, Range, Point, $$} = require 'atom'
DebuggerApi = require('debugger-api')

class CommandButtonView extends View
  @content: =>
    @button
      class: 'btn'
      click: 'triggerMe'
  
  commandsReady: ->
    [@kb] = atom.keymaps.findKeyBindings(command: @commandName)
    [@command] = (atom.commands
    .findCommands
      target: atom.workspaceView
    .filter (cmd) => cmd.name is @commandName)
    
    [kb,cmd,disp] = [@kb, @commandName, @command?.displayName]
    if kb?
      @append($$ ->
        @kbd _.humanizeKeystroke(kb.keystrokes), class: ''
        @span (disp ? cmd).split(':').pop()
      )
  
  triggerMe: ->
    @parentView.triggerCommand(@commandName)
    
  initialize: (suffix)->
    @commandName = 'atom-node-debug:'+suffix


module.exports =
class DebuggerView extends View

  @content: ->
    @div class: "tool-panel panel-bottom padded atom-node-debug--ui", =>
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
  initialize: (serializeState) ->
    @registerCommand 'atom-node-debug:debug-current-file',
    '.editor', =>@startSession()
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
  startSession: (port) ->
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
      
    for {lineNumber, scriptPath}, index in @getCurrentPauseLocations()
      continue unless scriptPath is editorPath
      marker = @createMarker(lineNumber, scriptPath)
      @editor.decorateMarker marker,
        type: 'line',
        class: 'and-current-pointer'
      @editor.decorateMarker marker,
        type: 'gutter',
        class: 'and-current-pointer'
      if index is 0
        @editor.decorateMarker marker,
          type: 'line',
          class: 'and-current-pointer--top'
        @editor.decorateMarker marker,
          type: 'gutter',
          class: 'and-current-pointer--top'
    
    for bp in @getBreakpoints()
      console.log bp
      {locations: [{lineNumber, scriptPath}]} = bp
      continue unless scriptPath is editorPath
      marker = @createMarker(lineNumber, scriptPath)
      @editor.decorateMarker marker,
        type: 'gutter',
        class: 'and-breakpoint'
      @editor.decorateMarker marker,
        type: 'line',
        class: 'and-breakpoint'


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

  endSession: ->
    @destroyAllMarkers()
    @childprocess?.kill()
    @bug?.close()
    @detach()
    
  serialize: ->

  destroy: ->
    @localCommandMap = null
    @endSession()
    

  ###
  DebuggerApi accessor functions.
  TODO: extract into a separate model class, so that this view can
        be reused for other debuggers!
  ###

  ###
  Startup
  ###
  startDebugger: (port) ->
    @bug = new DebuggerApi({debugPort: port})
    @bug.enable()
    @bug.on('Debugger.resumed', =>
      @clearCurrentPause()
      @updateMarkers()
      atom.workspaceView.removeClass('atom-node-debug--paused')
      return
    )
    @bug.on('Debugger.paused', (breakInfo)=>
      @setCurrentPause(breakInfo)
      @updateMarkers()
      atom.workspaceView.addClass('atom-node-debug--paused')
      return
    )



  ###
  Breakpoints
  ###
  breakpoints: []
  setBreakpoint: ({scriptPath, lineNumber}, done)->
    bp =
      url: url.format
        protocol: 'file'
        pathname: scriptPath
        slashes: true
      lineNumber: lineNumber
    console.log bp
    @bug.setBreakpointByUrl(bp, (err, {breakpointId, locations})=>
      if (err?) then console.error(err)
      else if not locations?[0]? then console.error("Couldn't set breakpoint.")
      else
        @breakpoints.push(
          breakpointId: breakpointId
          locations: locations.map (loc)=>@debuggerToAtomLocation(loc)
        )
        done()
    )
  removeBreakpoint: (id)->
    @breakpoints = @breakpoints.filter ({breakpointId})->breakpointId isnt id
  toggleBreakpoint: ({scriptPath, lineNumber}, done)->
    bp = @breakpoints.filter (bp)->
      not (scriptPath is bp.locations[0].scriptPath and
      lineNumber is bp.locations[0].lineNumber)
    if bp.length < @breakpoints.length
      @breakpoints = bp
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
  ###*
  @return array of {scriptPath, lineNumber}
  ###
  getCurrentPauseLocations: ->
    (@currentPause?.callFrames ? []).map ({location})=>
      @debuggerToAtomLocation(location)
  setCurrentPause: (@currentPause)->
  clearCurrentPause: ->
    @currentPause = null
    
  debuggerToAtomLocation: ({lineNumber, scriptId}) ->
    scriptPath: path.normalize(@bug.scripts.findScriptByID(scriptId).v8name)
    lineNumber: lineNumber
    
    
