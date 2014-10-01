{$$, Point, ScrollView} = require 'atom'

url = require 'url'

module.exports =
class CallFrameView extends ScrollView
  
  @content: ->
    @div class: 'debugger-call-frame', =>
      @h2 =>
        @a outlet: 'link', =>
          @span outlet: 'name'
          @span class: 'url', outlet: 'url'
          @span class: 'line', outlet: 'line'
      @ul outlet: 'scopes'
      @div outlet: 'thisObject'

  setModel: (@model)->
    @model.scopeChain[0].object.load()
    .then @updateView.bind(this)
    
  updateView: ->
    @link.attr('href', @model.location.scriptUrl)
    @name.text @model.functionName
    @url.text url.parse(@model.location.scriptUrl).pathname
    @line.text @model.location.lineNumber
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
      
    
