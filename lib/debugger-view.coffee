debug = require('debug')
debug.enable('node-inspector-api')

_ = require 'underscore-plus'
{View, Range, Point, $$} = require 'atom'
DebuggerApi = require('debugger-api')
spawn = require("child_process").spawn

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
      @div class: "inset-panel", =>
        @div class: "panel-heading", =>
          @div class: 'btn-toolbar pull-left', =>
            @div class: 'btn-group', =>
              @button 'Detach',
                click: 'endSession'
                class: 'btn'
          @div class: 'btn-toolbar pull-right', =>
            @div class: 'btn-group', =>
              @subview 'continue', new CommandButtonView('continue')
              @subview 'stepInto', new CommandButtonView('step-into')
              @subview 'stepOver', new CommandButtonView('step-over')
              @subview 'stepOut', new CommandButtonView('step-out')
          @span 'Debugging'
        @div class: "panel-body padded", 'Debugger starting', outlet: 'console'

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
    '.atom-node-debug--paused', =>
      @bug.resume()
      @bug.once('Debugger.resumed', => @decoration.destroy())

    btn.commandsReady() for btn in [@continue,@stepOver,@stepOut,@stepInto]

  localCommandMap: {}
  registerCommand: (name, filter, callback) ->
    atom.workspaceView.command name, filter, callback
    @localCommandMap[name] = callback
  triggerCommand: (name)->
    @localCommandMap[name]()

  startSession: (port) ->
    startDebug = (port) =>
      @bug = new DebuggerApi({debugPort: port})
      @bug.enable()
      @bug.on('Debugger.resumed', ->
        atom.workspaceView
        .removeClass('atom-node-debug--paused')
      )
      @bug.on('Debugger.paused', (breakInfo)=>
        location = breakInfo.callFrames[0].location
        console.log location
        script = @bug.scripts.findScriptByID(location.scriptId)
        console.log script
        
        ###
        TODO:
        find (or open!) editor by script path & switch to it.
        ###
        atom.workspaceView
        .addClass('atom-node-debug--paused')
        
        line = @editor.lineTextForBufferRow(location.lineNumber)
        @console.text("#{location.lineNumber}: #{line}")
        range = new Range(
          new Point(location.lineNumber,0),
          new Point(location.lineNumber, line.length-1))

        if not @marker?
          @marker = @editor.markBufferRange(range,
            persistent: false
          )
        else @marker.setBufferRange(range)
        
        @decoration = @editor.decorateMarker(@marker,
          type: 'line',
          class: 'and-breakpoint--current'
        )
        
        return
      )

    if port?
      startDebug(port)
    else
      @editor = atom.workspace.getActiveEditor()
      file = @editor.getPath()
      port = 5858 #maybe actually look for one?
      @childprocess = spawn("node", [
        "--debug-brk=" + port
        file
      ])
      @childprocess.stderr.once "data", -> startDebug(port)
      
    
    atom.workspaceView.prependToBottom(this)

  endSession: ->
    @childprocess?.kill()
    @bug?.close()
    
  # Returns an object that can be retrieved when package is activated
  serialize: ->

  # Tear down any state and detach
  destroy: ->
    @localCommandMap = null
    @childprocess?.kill()
    @bug?.close()
    @detach()
