
path = require('path')
url = require('url')

{WorkspaceView} = require 'atom'
Debugger = require '../lib/atom-node-debug'

describe "DebuggerView", ->

  activationPromise = null

  scriptPath = require.resolve('./fixtures/simple_program.js')
  scriptUrl = url.format
    protocol: 'file',
    slashes: 'true',
    pathname: scriptPath

  beforeEach ->
    atom.workspaceView = new WorkspaceView
    activationPromise = atom.packages.activatePackage('debugger')

  it "starts a debug session on debugger:toggle-debug-session", ->
    expect(atom.workspaceView.find('.debugger')).not.toExist()
    
    waitsForPromise ->
      atom.workspaceView.open(scriptPath)
      .then ->
        editorView = atom.workspaceView.getActiveView()
        editorView.trigger('debugger:toggle-debug-session')

    waitsForPromise =>
      activationPromise
      .then (@package) =>

    waitsFor ->
      @package.mainModule.debuggerView?.pauseLocation?
      
    runs ->
      location = @package.mainModule.debuggerView.pauseLocation
      expect(location.scriptUrl).toBe(scriptUrl)
