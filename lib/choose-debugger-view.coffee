{$, EditorView, Point, View} = require 'atom'

module.exports =
class ChooseDebuggerView extends View
  
  @content: ->
    @div class: 'overlay from-top', =>
      @subview 'miniEditor', new EditorView(mini: true)
      @div class: 'message', outlet: 'message'

  detaching: false

  initialize: (@debuggerView, state) ->
    atom.workspaceView.command 'debugger:connect', =>
      @toggle()
      false

    @miniEditor.setText(state?.text ? '')

    atom.workspaceView.on 'core:confirm', => @confirm()
    atom.workspaceView.on 'core:cancel', => @detach()

    @miniEditor.getModel().on 'will-insert-text', ({cancel, text}) ->
      # cancel() unless text.match(/[0-9]/)
      # TODO: validate ws url.
      
  serialize: ->
    text: @miniEditor.getText()

  toggle: ->
    if @hasParent()
      @detach()
    else
      @attach()

  detach: ->
    return unless @hasParent()

    @detaching = true
    miniEditorFocused = @miniEditor.isFocused

    super

    @restoreFocus() if miniEditorFocused
    @detaching = false

  confirm: ->
    return unless @hasParent()
    debugPort = @miniEditor.getText()
    @detach()
    # This is where we start the debugger.
    @debuggerView.toggleSession(debugPort)


  storeFocusedElement: ->
    @previouslyFocusedElement = $(':focus')

  restoreFocus: ->
    if @previouslyFocusedElement?.isOnDom()
      @previouslyFocusedElement.focus()
    else
      atom.workspaceView.focus()

  attach: ->
    if true #TODO: check whether we're already debugging.
      @storeFocusedElement()
      atom.workspaceView.append(this)
      @message.html """
      <p>
        Enter the front-end port of a node-inspector or the websocket address of
        a debugging Chrome instance.<br>
        <strong class="text-warning">NOTE: That is <em>not</em> the same thing
        as the node debug port. By default, it's 8080 for node-inspector.
        </strong>
      </p>
      """
      @miniEditor.focus()