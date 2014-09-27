_ = require 'underscore-plus'
{View, $$} = require 'atom'

module.exports =
class CommandButtonView extends View
  @content: =>
    @button
      class: 'btn'
      click: 'triggerMe'
  
  commandsReady: ->
    [@kb] = atom.keymaps.findKeyBindings(command: @commandName)
    [@command] = (atom.commands
    .findCommands
      target: atom.workspaceView
    .filter (cmd) => cmd.name is @commandName)
    
    [kb,cmd,disp] = [@kb, @commandName, @command?.displayName]
    if kb?
      @append($$ ->
        @kbd _.humanizeKeystroke(kb.keystrokes), class: ''
        @span (disp ? cmd).split(':').pop()
      )
  
  triggerMe: ->
    @parentView.triggerCommand(@commandName)
    
  initialize: (suffix)->
    @commandName = 'node-debug:'+suffix
