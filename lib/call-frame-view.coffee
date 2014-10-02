{$$, Point, ScrollView} = require 'atom'

url = require 'url'

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
    
  updateView: ->
    @scopes.empty()
    for scope in @model.scopeChain
      @scopes.append $$ ->
        @li =>
          @dl =>
            for prop in scope.object.properties
              @dt class: 'source js variable', prop.name
              @dd class: 'source js', prop.value?.description
      theThis = scope.thisObject
      if theThis?
        @thisObject.append $$ ->
          @h3 'this:'
          @dl outlet: 'thisObject', =>
            for prop in theThis.properties
              @dt class: 'variable', prop.name
              @dd prop.value?.description
      
    
