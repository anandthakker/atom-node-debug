url = require('url')
path = require('path')
fs = require('fs')

debug = require('debug')('atom-debugger:editor-controls')

{Range, Point} = require 'atom'
Q = require 'q'


#
# Keep track of the most recent Editor (i.e. open file), and the
# most recent Pane in which a TextEditor had focus.
#
# TODO: refactoring out the URL/location object awareness here would
# make this reuable in other packages.
module.exports=
class EditorControls
  constructor: ()->
    @activePaneItemChanged()
    @disposables = []
    @disposables.push atom.workspace.onDidChangeActivePaneItem(
      @activePaneItemChanged.bind(this))
  
  destroy: ->
    disposable.dispose() for disposable in @disposables
  
  onDidEditorChange: (@onEditorChange) ->
  
  editor: -> @editor

  # @param format Format resulting path as URL, even for local paths.
  editorPath: (format) ->
    if(@editor?.getPath()?)
      return @editor.getPath() unless format
      url.format
        protocol: 'file'
        slashes: 'true'
        pathname: @editor.getPath()
    else
      # try getting RemoteTextBuffer URL.
      @editor?.getBuffer()?.getRemoteUri() ? ''
    
  editorUrl: -> @editorPath(true)
  
  activePaneItemChanged: ->
    paneItem = atom.workspace.getActivePaneItem()
    if paneItem?.getBuffer?()?
      @lastEditorPane = atom.workspace.getActivePane()
      if paneItem isnt @editor
        @editor = paneItem
        @onEditorChange?()


  # Usage:
  # open(url, linenumber, [options])
  # open({scriptUrl, lineNumber}, [options])
  open: (scriptUrl, lineNumber, options={})->
    debug('open location', scriptUrl, lineNumber)
    
    if(typeof scriptUrl is 'object')
      options = lineNumber ? {}
      {scriptUrl, lineNumber} = scriptUrl
    
    # if it's remote, construct an atom:// uri to open the resource
    # with a RemoteTextBuffer
    scriptPath = if /^https?:/.test scriptUrl then url.format
      protocol: 'atom'
      slashes: true
      hostname: 'debugger'
      pathname: 'open'
      query: {url: scriptUrl}
    # if it's a file, just open the path.
    else if /^file/.test scriptUrl
      file = path.resolve url.parse(scriptUrl).pathname
      if fs.existsSync(file) then file
      else
        console.log "#{file} doesn't exist."
        undefined
    # if it's not a file:// or http(s)://, treat it as a path.
    else scriptUrl
        
    debug('scriptUrl', scriptUrl)
    debug('current editor', @editorUrl())
    if scriptUrl is @editorUrl()
      @editor.scrollToBufferPosition new Point(lineNumber, 0)
      debug('just scroll')
      return Q(@editor)
    
    @lastEditorPane.activate()
    options.initialLine = lineNumber
    atom.workspaceView.open(scriptPath, options)
    .then (@editor)->#just save editor.
