debug =
url =
RemoteTextBuffer =
EditorControls =
DebuggerApi =
DebuggerModel =
ChooseDebuggerView =
DebuggerView = null

loadPackageDependencies = ->
  if not debug?
    debug = require('debug')
    # debug.enable [
    #   'atom-debugger:backend'
    #   'atom-debugger:api'
    #   'atom-debugger:model'
    #   'atom-debugger:view'
    #   'atom-debugger:package'
    # ].join ','
    # debug.log = console.debug.bind(console)
    debug = debug('atom-debugger:package')

  debug('loading package deps')

  url ?= require('url')
  
  RemoteTextBuffer    ?= require './remote-text-buffer'
  EditorControls      ?= require './editor-controls'
  DebuggerApi         ?= require './api/debugger-api'
  DebuggerModel       ?= require './model/debugger-model'
  ChooseDebuggerView  ?= require './view/choose-debugger-view'
  DebuggerView        ?= require './view/debugger-view'



module.exports =
  chooseView: null
  debuggerView: null
  debuggerModel: null
  editorControls: null
  
  
  activate: (state) ->

    #
    # Require modules
    #
    
    loadPackageDependencies()

    debug('activating debugger package')
    
    #
    # Create/deserialize the main model.
    #

    @debuggerModel = new DebuggerModel(state?.debuggerModelState ? {},
      new DebuggerApi())
    
    #
    # Helpers
    #
    @editorControls = new EditorControls()
    
    #
    # Set up routes for atom://debugger/* uris
    #

    atom.workspace.addOpener (uri,opts)=>
      {protocol, host, pathname, query} = url.parse(uri, true)
      return unless (protocol is 'atom:' and host is 'debugger')

      switch pathname
        # open debugger view
        when '','/'
          @debuggerView ?= new DebuggerView(@debuggerModel, @editorControls)
        # open remote sources in a TextEditor for debugging browser scripts.
        when '/open' then RemoteTextBuffer.open(uri, query.url, opts)


    #
    # Set up commands
    #
    
    atom.commands.add 'atom-workspace',
      'debugger:connect': =>
        @chooseView ?= new ChooseDebuggerView(state?.chooseViewState ? {})
        @chooseView.toggle()
        .done ({portOrUrl, cancel}) => unless cancel
          @stopDebugging()
          @startDebugging(portOrUrl)
      'debugger:open-debug-view': ->
    
    atom.commands.add 'atom-text-editor',
      'debugger:toggle-debug-session': => @toggleDebugging()

  
  toggleDebugging: ->
    debug('toggleDebugging')
    if(@debuggerView?)
      @openDebugView()
      .done => @debuggerView.toggleSession()
    else @startDebugging()
  
  stopDebugging: ->
    @debuggerView?.endSession()
  
  openDebugView: ->
    activePane = atom.workspace.getActivePane()
    pane = atom.workspace.paneForUri('atom://debugger/')
    pane ?= activePane.splitDown({copyActiveItem: false})
    activePane.activate() #reactivate the editor we started from.
    atom.workspace.openUriInPane('atom://debugger/', pane, {changeFocus: false})

  startDebugging: (portOrUrl)->
    @openDebugView()
    .done (debuggerView)->
      debug('start debugging', portOrUrl)
      debuggerView.endSession()
      debuggerView.toggleSession(portOrUrl)

  deactivate: ->
    @stopDebugging()
    @chooseView?.destroy?()
    @debuggerView?.destroy?()
    @editorControls?.destroy?()
    @debuggerModel.close()
    @debuggerView = @chooseView = @editorControls = null
    
    # TODO: ???
    atom.workspace.getPaneItems().forEach (item)->
      if item instanceof RemoteTextBuffer
        atom.workspace.getActivePane().destroyItem(item)

  serialize: ->
    chooseViewState: @chooseView?.serialize() ? {}
    debuggerModelState: @debuggerModel.serialize()
