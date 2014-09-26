ChoosePortView = require './choose-port-view'
DebuggerView = require './debugger-view'

module.exports =
  choosePortView: null
  debuggerView: null

  activate: (state) ->
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
