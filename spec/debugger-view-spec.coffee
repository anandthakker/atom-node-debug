
path = require('path')

{WorkspaceView} = require 'atom'
Debugger = require '../lib/atom-node-debug'

describe "DebuggerView", ->

  activationPromise = null

  beforeEach ->
    atom.workspaceView = new WorkspaceView
    activationPromise = atom.packages.activatePackage('debugger')

  fit "creates the view", ->
    expect(atom.workspaceView.find('.debugger')).not.toExist()
    
    waitsForPromise ->
      atom.workspaceView.open(
        path.join(__dirname, 'fixtures', 'simple_program.js'))
      .then ->
        editorView = atom.workspaceView.getActiveView()
        editorView.trigger('debugger:toggle-debug-session')

    waitsForPromise =>
      activationPromise
      .then (@package) =>

    waitsFor ->
      @package.mainModule.debuggerView?
      
    runs ->
      console.log @package.mainModule.debuggerView
