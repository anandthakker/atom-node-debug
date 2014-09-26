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
    activationPromise = atom.packages.activatePackage('atom-node-debug')

  describe "when the atom-node-debug:toggle event is triggered", ->
    it "attaches and then detaches the view", ->
      expect(atom.workspaceView.find('.atom-node-debug')).not.toExist()

      # This is an activation event, triggering it will cause the package to be
      # activated.
      atom.workspaceView.trigger 'atom-node-debug:toggle'

      waitsForPromise ->
        activationPromise

      runs ->
        expect(atom.workspaceView.find('.atom-node-debug')).toExist()
        atom.workspaceView.trigger 'atom-node-debug:toggle'
        expect(atom.workspaceView.find('.atom-node-debug')).not.toExist()
