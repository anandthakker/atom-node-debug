{$, $$, Point, View} = require 'atom'

url = require 'url'

Q = require('q')

module.exports =
class RemoteObjectView extends View
  
  @content: (model, label) ->
    @div =>
      @span label ? model.description
      @a click: "toggle", "+"
      @div outlet: "contents"

  initialize: (@model, @label)->
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
    .done =>
      @append @contents
    
  load: ->
    return Q() if @loaded or not @model.load?
    promise = @model.load()
    promise.then =>
      @loaded = true
      @updateView()
    
  updateView: ->
    @contents.empty()
    @contents.append(dl = $('<dl></dl>'))
    for prop in @model.properties
      dl.append($('<dt class="source js variable">'+prop.name+'</dt>'))
      dl.append(dd = $('<dd></dd>'))
      if (id = prop.value.objectId?)
        dd.append new RemoteObjectView(prop.value)
      else
        dd.text(prop.value?.description)
    
