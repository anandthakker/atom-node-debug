
path = require('path')
url = require('url')

Q = require('q')

debug = require('debug')('atom-debugger:view')

{WorkspaceView} = require 'atom'
Debugger = require '../lib/atom-node-debug'

fdescribe "DebuggerView", ->

  pkg = null
  debuggerView = null
  activationPromise = null

  scriptUrl = (scriptPath) ->
    url.format
      protocol: 'file',
      slashes: 'true',
      pathname: scriptPath


  beforeEach ->
    atom.workspaceView = new WorkspaceView
    activationPromise = atom.packages.activatePackage('debugger')
    # need the grammar for callframe / watch syntax highlighting.
    waitsForPromise -> atom.packages.activatePackage('language-javascript')
      
  afterEach ->
    waitsForPromise ->
      debuggerView.endSession()
      
  setup = (scriptPath) ->
    console.log "SETTING UP", scriptPath
    expect(atom.workspaceView.find('.debugger')).not.toExist()
    
    waitsForPromise ->
      atom.workspaceView.open(scriptPath)
      .then ->
        editorView = atom.workspaceView.getActiveView()
        editorView.trigger('debugger:toggle-debug-session')

    waitsForPromise ->
      activationPromise.then (pack) -> pkg = pack

    waitsFor ->
      debuggerView = pkg.mainModule.debuggerView
      debuggerView?.pauseLocation?
      
  it "starts a debug session on debugger:toggle-debug-session", ->
    scriptPath = require.resolve('./fixtures/simple_program.js')
    setup(scriptPath)
    
    runs ->
      location = pkg.mainModule.debuggerView.pauseLocation
      expect(location.scriptUrl).toBe(scriptUrl(scriptPath))
      
  it "correctly switches files when execution pauses", ->
    scriptPath1 = require.resolve('./fixtures/multi_file_1.js')
    scriptPath2 = require.resolve('./fixtures/multi_file_2.js')
    setup(scriptPath1)
      
    runs ->
      debuggerView = pkg.mainModule.debuggerView
      debuggerView.trigger('debugger:step-over')
    
    waitsFor ->
      debuggerView.pauseLocation?.lineNumber is 3
    
    runs -> debuggerView.trigger('debugger:step-into')
    
    waitsFor ->
      atom.workspace.getActivePaneItem()?.getPath?() isnt scriptPath1
      
    runs ->
      expect(atom.workspace.getActivePaneItem().getPath()).toBe(scriptPath2)
