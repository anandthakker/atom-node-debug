{$, $$, Point, ScrollView} = require 'atom'

url = require 'url'

RemoteObjectView = require './remote-object-view'

module.exports =
class CallFrameView extends ScrollView
  
  @content: (model) ->
    @div class: 'tool-panel bordered debugger-call-frame', =>
      @div class: 'panel-heading', click: 'toggle', =>
        @a outlet: 'link', =>
          @span class: 'url', url.parse(model.location.scriptUrl).pathname
          @span class: 'line', model.location.lineNumber
      @div class: 'panel-body', outlet: 'contents', =>
        @ul outlet: 'scopes', =>
          for scope in model.scopeChain
            @li =>
              @subview scope.object.objectId,
                new RemoteObjectView(scope.object, 'scope ('+scope.type+')')
        if model.this?
          @div =>
            @subview 'thisObject', new RemoteObjectView(model.this, 'this')

  initialize: (@model, @onExpand)->
    @collapse()
    this[@model.scopeChain[0].object.objectId].show()
  
  toggle: ->
    if @contents.hasParent() then @collapse()
    else @expand()
  collapse: ->
    return unless @contents.hasParent()
    @contents.detach()
  expand: ->
    return if @contents.hasParent()
    @append @contents
    @onExpand?(this)
          
    
