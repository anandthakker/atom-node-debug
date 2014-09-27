module.exports =
  choosePortView: null
  debuggerView: null

  activate: (state) ->
    # Perform `require`s after activation -- ugly but faster, according to:
    # https://discuss.atom.io/t/how-to-speed-up-your-packages/10903
    require('debug').enable([
      'node-inspector-api'
      'atom-debugger'
      'node-inspector:*'
    ].join(','))

    debug = require('debug')('atom-debugger')
    ChoosePortView = require './choose-port-view'
    DebuggerView = require './debugger-view'

    debug('activating debugger package')
    @debuggerView = new DebuggerView(state.debuggerViewState)
    @choosePortView = new ChoosePortView(
      @debuggerView,
      state.choosePortViewState)

  deactivate: ->
    @choosePortView.destroy()
    @debuggerView.destroy()

  serialize: ->
    choosePortViewState: @choosePortView.serialize()
    debuggerViewState: @debuggerView.serialize()
