{WorkspaceView} = require 'atom'
Debugger = require '../lib/atom-node-debug'

describe "Debugger", ->
  activationPromise = null

  beforeEach ->
    atom.workspaceView = new WorkspaceView
    activationPromise = atom.packages.activatePackage('debugger')

  describe "when the node-debug:toggle event is triggered", ->
    it "attaches and then detaches the view", ->
      # expect(atom.workspaceView.find('.node-debug')).not.toExist()
      # 
      # # This is an activation event, triggering it will cause the package to be
      # # activated.
      # atom.workspaceView.trigger 'node-debug:toggle'
      #
      # waitsForPromise ->
      #   activationPromise
      #
      # runs ->
      #   expect(atom.workspaceView.find('.node-debug')).toExist()
      #   atom.workspaceView.trigger 'node-debug:toggle'
      #   expect(atom.workspaceView.find('.node-debug')).not.toExist()
