{WorkspaceView} = require 'atom'
AtomNodeDebug = require '../lib/atom-node-debug'

# Use the command `window:run-package-specs` (cmd-alt-ctrl-p) to run specs.
#
# To run a specific `it` or `describe` block add an `f` to the front (e.g. `fit`
# or `fdescribe`). Remove the `f` to unfocus the block.

describe "AtomNodeDebug", ->
  activationPromise = null

  beforeEach ->
    atom.workspaceView = new WorkspaceView
    activationPromise = atom.packages.activatePackage('node-debug')

  describe "when the node-debug:toggle event is triggered", ->
    it "attaches and then detaches the view", ->
      expect(atom.workspaceView.find('.node-debug')).not.toExist()

      # This is an activation event, triggering it will cause the package to be
      # activated.
      atom.workspaceView.trigger 'node-debug:toggle'

      waitsForPromise ->
        activationPromise

      runs ->
        expect(atom.workspaceView.find('.node-debug')).toExist()
        atom.workspaceView.trigger 'node-debug:toggle'
        expect(atom.workspaceView.find('.node-debug')).not.toExist()
