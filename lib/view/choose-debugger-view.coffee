{$, EditorView, Point, View} = require 'atom'

Q = require 'q'

module.exports =
class ChooseDebuggerView extends View
  
  @content: ->
    @div class: 'overlay from-top', =>
      @subview 'miniEditor', new EditorView(mini: true)
      @div class: 'message', outlet: 'message'

  detaching: false

  initialize: (state) ->

    @miniEditor.setText(state?.text ? '')

    atom.workspaceView.on 'core:confirm', => @confirm()
    atom.workspaceView.on 'core:cancel', => @cancel()
    @miniEditor.getModel().on 'will-insert-text', ({cancel, text}) ->
      # cancel() unless text.match(/[0-9]/)
      # TODO: validate ws url.
      
  serialize: ->
    text: @miniEditor.getText()

  toggle: ->
    if @hasParent()
      @cancel()
    else
      @deferred = Q.defer()
      @attach()
    @deferred.promise

  detach: ->
    return unless @hasParent()

    @detaching = true
    miniEditorFocused = @miniEditor.isFocused

    super

    @restoreFocus() if miniEditorFocused
    @detaching = false

  cancel: ->
    @deferred.resolve({cancel: true})
    @detach()
    
  confirm: ->
    return unless @hasParent()
    portOrUrl = @miniEditor.getText()
    @deferred.resolve({portOrUrl})
    @detach()

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
