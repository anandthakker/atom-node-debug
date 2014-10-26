{$, $$, Point, View} = require 'atom'

url = require 'url'

Q = require('q')

module.exports =
class RemoteObjectView extends View
  
  @content: (model, label) ->
    @div class: 'debugger-remote-object', =>
      @span class: 'source variable js name', click: 'toggle', label
      @span class: 'source support class js description', click: 'toggle', model.description
      @div class: 'properties', outlet: 'contents'

  initialize: (@model, @label)->
    @contents.detach()
  
  toggle: ->
    if @contents.hasParent() then @hide()
    else @show()
  hide: ->
    return unless @contents.hasParent()
    @removeClass('open')
    @contents.detach()
  show: ->
    return if @contents.hasParent()
    @addClass('open')
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
    for prop in @model.properties
      @contents.append(div = $('<div class="property"></div>'))
      
      if (prop.value.type is 'object' and prop.value.objectId?)
        # If its an object with an id, make a new remote object that can
        # itself be expanded.
        div.append new RemoteObjectView(prop.value, prop.name)

      else
        # Otherwise, try to (crudely) syntax highlight it.
        div.append($('<span class="source variable js name">'+
          prop.name+'</span>'))
        div.append(value = $('<span class="source js description"></span>'))

        if prop.value.type is 'string'
          prop.value.description = '"' + prop.value.description + '"'

        # This is a hacky way to use the grammar, but I'm calling it good enough
        # for this simple case.
        code = prop.value.description
        grammar = atom.syntax.grammarForScopeName('source.js')
        result = grammar.tokenizeLine code
        for token in result.tokens
          span = $("<span></span>")
          span.text token.value
          
          classes = token.scopes
          .filter (scope)->scope isnt 'source.js' #already wrapped with this.
          .map (scope)->scope.replace('.',' ')
          .join ' '
          span.addClass classes
          value.append span
