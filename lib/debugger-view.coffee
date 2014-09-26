debug = require('debug')
# debug.enable('node-inspector-api')

_ = require 'underscore-plus'
spawn = require('child_process').spawn
path = require('path')

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

    btn.commandsReady() for btn in [@continue,@stepOver,@stepOut,@stepInto]


  localCommandMap: {}
  registerCommand: (name, filter, callback) ->
    atom.workspaceView.command name, callback
    @localCommandMap[name] = callback
  triggerCommand: (name)->
    @localCommandMap[name]()


  startSession: (port) ->
    @activePaneItemChanged()
    atom.workspaceView.on 'pane-container:active-pane-item-changed', =>
      @activePaneItemChanged()
    atom.workspaceView.prependToBottom(this)

    startDebug = (port) =>
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

    if port?
      startDebug(port)
    else
      @editor = atom.workspace.getActiveEditor()
      file = @editor.getPath()
      port = 5858 #umm... actually look for one?
      @childprocess = spawn("node",
        params=["--debug-brk=" + port,file ])
      @childprocess.stderr.once 'data', -> startDebug(port)

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
  updateMarkers: ->
    @destroyAllMarkers()
    editorPath = @editor.getPath()
    return unless editorPath?
    editorPath = path.normalize(editorPath)

    for {lineNumber, scriptPath}, index in @getCurrentPauseLocations()
      continue unless scriptPath is editorPath
      line = @editor.lineTextForBufferRow(lineNumber)
      range = new Range(new Point(lineNumber,0),
                        new Point(lineNumber, line.length-1))

      @markers.push(marker = @editor.markBufferRange(range))
      
      @editor.decorateMarker marker,
        type: 'line',
        class: 'and-current-pointer'
      if index is 0
        @editor.decorateMarker marker,
          type: 'line',
          class: 'and-current-pointer--top'

  destroyAllMarkers: ->
    marker.destroy() for marker in @markers



  currentPause: null
  ###*
  @return array of {scriptPath, lineNumber}
  ###
  getCurrentPauseLocations: ->
    (@currentPause?.callFrames ? []).map ({location:{lineNumber, scriptId}})=>
      scriptPath: path.normalize(@bug.scripts.findScriptByID(scriptId).v8name)
      lineNumber: lineNumber
  setCurrentPause: (@currentPause)->
  clearCurrentPause: ->
    @currentPause = null
    

  endSession: ->
    @destroyAllMarkers()
    @childprocess?.kill()
    @bug?.close()
    @detach()
    
  # Returns an object that can be retrieved when package is activated
  serialize: ->

  # Tear down any state and detach
  destroy: ->
    @localCommandMap = null
    @endSession()
