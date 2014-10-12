
module.exports =
  chooseView: null
  debuggerView: null
  debuggerModel: null
  
  activate: (state) ->

    #
    # Require modules
    #
    
    debug = require('debug')
    debug.enable([
      # 'atom-debugger:backend'
      # 'atom-debugger:api'
      # 'atom-debugger:model'
      # 'atom-debugger:view'
      # 'atom-debugger:package'
    ].join(','))
    debug.log = console.debug.bind(console)
    debug = debug('atom-debugger:package')

    url = require('url')
    
    DebuggerApi = require './debugger-api'
    RemoteTextBuffer = require './remote-text-buffer'
    ChooseDebuggerView = require './choose-debugger-view'
    DebuggerView = require './debugger-view'
    DebuggerModel = require './debugger-model'

    debug('activating debugger package')
    
    #
    # Create/deserialize the main model.
    #

    @debuggerModel = new DebuggerModel(state?.debuggerModelState ? {},
      new DebuggerApi())
    
    #
    # Set up commands
    #
    
    atom.workspaceView.command 'debugger:connect', =>
      @chooseView ?= new ChooseDebuggerView(state?.chooseViewState ? {})
      @chooseView.toggle()
      .done ({portOrUrl, cancel}) => unless cancel
        @stopDebugging()
        @startDebugging(portOrUrl)
    
    atom.workspaceView.command 'debugger:open-debug-view', '.workspace', =>
      
    atom.workspaceView.command 'debugger:toggle-debug-session', '.editor', =>
      @toggleDebugging()

    #
    # Set up routes for atom://debugger/* uris
    #

    atom.workspace.registerOpener (uri,opts)=>
      {protocol, host, pathname, query} = url.parse(uri, true)
      return unless (protocol is 'atom:' and host is 'debugger')

      switch pathname
        # open remote sources in a TextEditor for debugging browser scripts.
        when '/open' then RemoteTextBuffer.open(uri, query.url, opts)
        when '','/'
          @debuggerView ? (@debuggerView = new DebuggerView(@debuggerModel))

  
  toggleDebugging: ->
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
    atom.workspace.openUriInPane('atom://debugger/',
      pane, {changeFocus: false})

  startDebugging: (portOrUrl)->
    @openDebugView()
    .done (debuggerView)->
      debuggerView.endSession()
      debuggerView.toggleSession(portOrUrl)

  deactivate: ->
    @stopDebugging()
    @chooseView?.destroy()
    @debuggerView?.destroy()
    @debuggerModel.close()
    
    # TODO: ???
    atom.workspace.getPaneItems().forEach (item)->
      if item instanceof RemoteTextBuffer
        atom.workspace.getActivePane().destroyItem(item)

  serialize: ->
    chooseViewState: @chooseView?.serialize() ? {}
    debuggerModelState: @debuggerModel.serialize()
