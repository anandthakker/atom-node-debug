{$, EditorView, Point, View} = require 'atom'

module.exports =
class ChoosePortView extends View
  
  @content: ->
    @div class: 'choose-port overlay from-top mini', =>
      @subview 'miniEditor', new EditorView(mini: true)
      @div class: 'message', outlet: 'message'

  detaching: false

  initialize: (@debuggerView) ->
    atom.workspaceView.command 'atom-node-debug:connect', '.editor', =>
      @toggle()
      false

    @miniEditor.hiddenInput.on 'focusout', => @detach() unless @detaching
    @on 'core:confirm', => @confirm()
    @on 'core:cancel', => @detach()

    @miniEditor.getModel().on 'will-insert-text', ({cancel, text}) ->
      cancel() unless text.match(/[0-9]/)

  toggle: ->
    if @hasParent()
      @detach()
    else
      @attach()

  detach: ->
    return unless @hasParent()

    @detaching = true
    miniEditorFocused = @miniEditor.isFocused
    @miniEditor.setText('')

    super

    @restoreFocus() if miniEditorFocused
    @detaching = false

  confirm: ->
    debugPort = @miniEditor.getText()
    # editorView = atom.workspaceView.getActiveView()

    @detach()

    if debugPort.length
      debugPort = parseInt(debugPort)
    else
      debugPort = null
    
    # This is where we start the debugger.
    @debuggerView.startSession(debugPort)


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
        Enter port of running debugger or leave blank to debug current file.
      </p>
      <p>
        If the former, make sure node is debugging:<br>
        <code>node --debug-brk=PORT</code>
      </p>
      """
      @miniEditor.focus()
