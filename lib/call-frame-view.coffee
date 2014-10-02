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
        @ul outlet: 'scopes'
        @div outlet: 'thisObject'

  initialize: (@model, @onShow)->
    @contents.detach()
  
  toggle: ->
    if @contents.hasParent() then @hide()
    else @show()
  hide: ->
    return unless @contents.hasParent()
    @contents.detach()
  show: ->
    return if @contents.hasParent()
    @load()
    @append @contents
    @onShow?(this)
    
  load: ->
    return if @loaded
    @model.scopeChain[0].object.load()
    .then =>
      @loaded = true
      @updateView()

    
  # TODO: just move this into @content()
  updateView: ->
    @scopes.empty()
    for scope in @model.scopeChain
      li = $('<li></li>')
      @scopes.append(li)
      li.append(new RemoteObjectView(scope.object, 'scope ('+scope.type+')'))
      
    theThis = scope['this']
    if theThis?
      @thisObject.append new RemoteObjectView(theThis, 'this')
      
    
