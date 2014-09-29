module.exports =
  chooseDebuggerView: null
  debuggerView: null
  debuggerModel: null

  activate: (state) ->
    # Perform `require`s after activation -- ugly but faster, according to:
    # https://discuss.atom.io/t/how-to-speed-up-your-packages/10903
    
    require('debug').enable([
      'atom-debugger:backend'
      'atom-debugger:api'
      'atom-debugger:model'
      'atom-debugger:view'
      'atom-debugger:package'
    ].join(','))

    debug = require('debug')('atom-debugger:package')
    url = require('url')
    
    ChooseDebuggerView = require './choose-debugger-view'
    DebuggerView = require './debugger-view'
    DebuggerModel = require './debugger-model'
    RemoteTextBuffer = require './remote-text-buffer'

    debug('activating debugger package')
    
    @debuggerModel = new DebuggerModel(state?.debuggerModelState ? {})
    @debuggerView = new DebuggerView(@debuggerModel)
    @chooseDebuggerView = new ChooseDebuggerView(
      @debuggerView,
      state.chooseDebuggerViewState)

    # allows us to seamlessly open remote sources in an editor
    # for debugging browser scripts.
    atom.workspace.registerOpener (uri,opts)->
      {protocol, host, pathname, query} = url.parse(uri, true)
      debug('opener', uri, protocol, host, pathname, query)
      return unless (
        protocol is 'atom:' and
        host is 'debugger' and
        pathname is '/open')

      RemoteTextBuffer.open(query.url, opts)
        
  deactivate: ->
    @chooseDebuggerView.destroy()
    @debuggerView.destroy()
    atom.workspace.unregisterOpener @remoteSourceOpener

  serialize: ->
    chooseDebuggerViewState: @chooseDebuggerView.serialize()
    debuggerModelState: @debuggerModel.serialize()
