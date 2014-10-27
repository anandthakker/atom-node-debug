path = require('path')
url = require('url')

Q = require('q')

{nodeDebug, nodeInspector} = require './spec-helper'

debug = require('debug')('atom-debugger:view')

{WorkspaceView} = require 'atom'
Debugger = require '../lib/atom-node-debug'
DebuggerView = require '../lib/view/debugger-view'
EditorControls = require '../lib/editor-controls'


describe "DebuggerView", ->

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

  commonTestSuite = (setup) ->
    it "starts a debug session on debugger:toggle-debug-session", ->
      scriptPath = require.resolve('./fixtures/simple_program.js')
      setup(scriptPath)
      
      runs ->
        location = debuggerView.pauseLocation
        expect(location.scriptUrl).toBe(scriptUrl(scriptPath))
        
    it "correctly switches files when execution pauses", ->
      scriptPath1 = require.resolve('./fixtures/multi_file_1.js')
      scriptPath2 = require.resolve('./fixtures/multi_file_2.js')
      setup(scriptPath1)

      pauseLocation = null
      runs -> debuggerView.trigger('debugger:step-over')
      waitsFor -> debuggerView.pauseLocation?.lineNumber is 3
      runs -> debuggerView.trigger('debugger:step-into')

      waitsFor ->
        atom.workspace.getActivePaneItem()?.getPath?() isnt scriptPath1

      runs ->
        expect(atom.workspace.getActivePaneItem().getPath()).toBe(scriptPath2)
        pauseLocation = debuggerView.pauseLocation
        debuggerView.trigger('debugger:step-out')

      waitsFor ->
        (debuggerView.pauseLocation isnt pauseLocation) and
        (debuggerView.pauseLocation?.scriptUrl?)

      runs ->
        expect(atom.workspace.getActivePaneItem().getPath()).toBe(scriptPath1)


  describe 'debugging current file', ->
    setup = (scriptPath) ->
      waitsForPromise ->
        atom.workspaceView.open(scriptPath)
        .then ->
          editorView = atom.workspaceView.getActiveView()
          editorView.trigger('debugger:toggle-debug-session')

      waitsForPromise ->
        activationPromise.then (pack)->pkg=pack

      waitsFor ->
        debuggerView = pkg.mainModule.debuggerView
        debuggerView?.pauseLocation?.scriptUrl?
      
      runs ->
        console.log 'setup complete for ', scriptPath
    
    commonTestSuite(setup)
    
  describe 'attach to running debugger', ->
    nodeInspectorServer = null
    debuggedProcess = null
    wsUrl = null
  
    setup = (scriptPath) ->
      waitsForPromise ->
        nodeInspector(scriptPath)
        .then ({url, server, child}) ->
          waits(300)
          wsUrl = url
          nodeInspectorServer = server
          debuggedProcess = child
        .then ->
          atom.workspaceView.trigger 'debugger:connect'
  
      waitsForPromise ->
        activationPromise.then (pack)->pkg=pack
  
      waitsFor ->
        atom.workspaceView.find('.debugger-connect')
      
      runs ->
        pkg.mainModule.chooseView.miniEditor.setText(wsUrl)
        atom.workspaceView.trigger 'core:confirm'
  
      waitsFor ->
        debuggerView = pkg.mainModule.debuggerView
        debuggerView?.pauseLocation?.scriptUrl?
      
    afterEach ->
      debuggerModel?.close()
      nodeInspectorServer?.close()
      debuggedProcess?.kill()
      debuggerModel = nodeInspectorServer = debuggedProcess = null
      
    commonTestSuite(setup)

  
  debug('blah')
  it 'handles pause in unparsed/unknown script', ->
    scriptPath = require.resolve('./fixtures/simple_program.js')
    bugger =
      connect: (wsurl,@onpause,@onresume,@onscript)->
      pauses: []
      getCurrentPauseLocations: -> @pauses
      getBreakpoints: -> []
      getCallFrames: -> []
      close: -> Q(true)
    
    debuggerView = new DebuggerView(bugger, new EditorControls())
    
    debuggerView.startSession('ws://dummy:1729/')
    
    bugger.pauses.push
      scriptId: "60"
      lineNumber: 3
      columnNumber: 0
    bugger.onpause bugger.pauses[0]

    waitsFor -> debuggerView.pauseLocation?
    
    runs ->
      waits(300)
      expect(debuggerView.pauseLocation.scriptUrl).not.toBeDefined()
      expect(atom.workspace.getActivePaneItem()).toBeFalsy()

      bugger.onscript
        scriptId: '60'
        sourceURL: scriptUrl(scriptPath)
      
    waitsFor -> debuggerView.pauseLocation?.scriptUrl?
    waitsFor -> atom.workspace.getActivePaneItem()?.getPath?()?
    runs ->
      expect(atom.workspace.getActivePaneItem().getPath()).toBe(scriptPath)
