{View, Range, Point} = require 'atom'
debug = require('debug')
# debug.enable('node-inspector-api')
DebuggerApi = require('debugger-api')

#testing only
spawn = require("child_process").spawn

module.exports =
class DebuggerView extends View
  @content: ->
    @div class: "tool-panel panel-bottom padded", =>
      @div class: "inset-panel", =>
        @div class: "panel-heading", =>
          @div class: 'btn-toolbar pull-left', =>
            @div class: 'btn-group', =>
              @button class: 'btn', 'Detach', click: 'endSession'
          @div class: 'btn-toolbar pull-right', =>
            @div class: 'btn-group', =>
              @button class: 'btn', 'Continue', click: 'resume'
              @button class: 'btn', 'Step Over', click: 'stepOver'
              @button class: 'btn', 'Step Into', click: 'stepInto'
              @button class: 'btn', 'Step Out', click: 'stepOut'
          @span 'Debugging'
        @div class: "panel-body padded", 'Debugger starting', outlet: 'console'

  startSession: (port)->
    startDebug = (port) =>
      @bug = new DebuggerApi({debugPort: port})
      @bug.enable()
      @bug.on('Debugger.paused', (breakInfo)=>
        location = breakInfo.callFrames[0].location
        console.log location
        script = @bug.scripts.findScriptByID(location.scriptId)
        console.log script
        
        ###
        TODO:
        find (or open!) editor by script path & switch to it.
        ###
        
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
        
        decoration = @editor.decorateMarker(@marker,
          type: 'line',
          class: 'highlight-info'
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

  endSession: -> @bug.close()
  resume: -> @bug.resume()
  stepOver: -> @bug.stepOver()
  stepInto: -> @bug.stepInto()
  stepOut: -> @bug.stepOut()
  
  initialize: (serializeState) ->
    
  # Returns an object that can be retrieved when package is activated
  serialize: ->

  # Tear down any state and detach
  destroy: ->
    @childprocess?.kill()
    @debugSession?.close()
    @detach()
