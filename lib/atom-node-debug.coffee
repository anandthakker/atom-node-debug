module.exports =
  chooseDebuggerView: null
  debuggerView: null
  debuggerModel: null

  activate: (state) ->
    # Perform `require`s after activation -- ugly but faster, according to:
    # https://discuss.atom.io/t/how-to-speed-up-your-packages/10903
    # require('debug').enable([
    #   'atom-debugger:*'
    # ].join(','))

    debug = require('debug')('atom-debugger:package')
    ChooseDebuggerView = require './choose-debugger-view'
    DebuggerView = require './debugger-view'
    DebuggerModel = require './debugger-model'

    debug('activating debugger package')
    
    @debuggerModel = new DebuggerModel(state?.debuggerModelState ? {})
    @debuggerView = new DebuggerView(@debuggerModel)
    @chooseDebuggerView = new ChooseDebuggerView(
      @debuggerView,
      state.choosePortViewState)

  deactivate: ->
    @chooseDebuggerView.destroy()
    @debuggerView.destroy()

  serialize: ->
    choosePortViewState: @chooseDebuggerView.serialize()
    debuggerModelState: @debuggerModel.serialize()
