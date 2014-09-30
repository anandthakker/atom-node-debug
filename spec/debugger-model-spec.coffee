url = require 'url'
Q = require 'q'
{nodeDebug, nodeInspector} = require './spec-helper'

debug = require('debug')
debug.enable([
  # 'atom-debugger:backend'
  # 'atom-debugger:api'
  # 'atom-debugger:model'
  # 'atom-debugger:view'
  # 'atom-debugger:package'
].join(','))
debug.log = console.debug.bind(console)


DebuggerModel = require '../lib/debugger-model.coffee'

describe 'DebuggerModel', ->

  nodeInspectorServer = null
  debuggedProcess = null

  scriptUrl = null
  wsUrl = null
  debuggerModel = null
  onPause = null
  onResume = null

  beforeEach ->
    onPause = jasmine.createSpy('onPauseSpy')
    onResume = jasmine.createSpy('onResumeSpy')
    scriptPath = require.resolve('./fixtures/simple_program.js')
    scriptUrl = url.format
      protocol: 'file',
      slashes: 'true',
      pathname: scriptPath
      
    waitsForPromise ->
      nodeInspector(scriptPath)
      .then ({url, server, child}) ->
        waits(300)
        wsUrl = url
        nodeInspectorServer = server
        debuggedProcess = child
        debuggerModel = new DebuggerModel()
        
  afterEach ->
    debuggerModel?.close()
    nodeInspectorServer?.close()
    debuggedProcess?.kill()
    debuggerModel = nodeInspectorServer = debuggedProcess = null

  it 'connects', ->
    waitsForPromise ->
      debuggerModel.connect(wsUrl, onPause, onResume)
      .then ->
        expect(debuggerModel.isActive).toBe(true) #duh
        
  it 'receives pause event at a known script url after connecting', ->
    waitsForPromise ->
      debuggerModel.connect(wsUrl, onPause, onResume).then ->
        waitsFor ->
          onPause.callCount > 0
        runs ->
          [pauseLoc] = onPause.mostRecentCall.args
          expect(pauseLoc.lineNumber).toBeDefined()
          expect(pauseLoc.scriptUrl).toBe(scriptUrl)


  describe 'breakpoints', ->
    checkBreakpoints = (count)->
      bps = debuggerModel.getBreakpoints()
      expect(bps.length).toBe(count)
      bps.forEach (bp)->expect(bp.locations[0].scriptUrl).toBe scriptUrl
      Q()

    it 'actually stops at a breakpoint', ->
      waitsForPromise ->
        debuggerModel.toggleBreakpoint({scriptUrl, lineNumber: 5})
        .then ->
          debuggerModel.connect(wsUrl, onPause, onResume)
        .then ->
          waitsFor ->
            onPause.callCount is 1
          runs ->
            debuggerModel.resume()
          waitsFor ->
            onPause.callCount is 2
          runs ->
            expect(onPause.mostRecentCall.args[0].lineNumber).toBe 5

    it 'puts a scriptUrl on breakpoint locations', ->
      waitsForPromise ->
        debuggerModel.toggleBreakpoint({scriptUrl, lineNumber: 3})
        .then -> checkBreakpoints(1)
        .then -> debuggerModel.connect(wsUrl, onPause, onResume)
        .then -> debuggerModel.toggleBreakpoint({scriptUrl, lineNumber: 4})
        .then -> checkBreakpoints(2)
        .then -> debuggerModel.close()
        .then -> debuggerModel.toggleBreakpoint({scriptUrl, lineNumber: 5})
        .then -> checkBreakpoints(3)
          
    it 'toggles breakpoints while disconnected', ->
      waitsForPromise ->
        debuggerModel.toggleBreakpoint({scriptUrl, lineNumber: 2})
        .then -> checkBreakpoints(1)
        .then -> debuggerModel.toggleBreakpoint({scriptUrl, lineNumber: 2})
        .then -> checkBreakpoints(0)

    it 'toggles breakpoints while connected', ->
      waitsForPromise ->
        debuggerModel.connect(wsUrl, onPause, onResume)
        .then -> debuggerModel.toggleBreakpoint({scriptUrl, lineNumber: 2})
        .then -> checkBreakpoints(1)
        .then -> debuggerModel.toggleBreakpoint({scriptUrl, lineNumber: 2})
        .then -> checkBreakpoints(0)
    
    it 'while connected, toggles breakpoints that were set while disconnected',
    -> waitsForPromise ->
      debuggerModel.toggleBreakpoint({scriptUrl, lineNumber: 2})
      .then -> checkBreakpoints(1)
      .then -> debuggerModel.connect(wsUrl, onPause, onResume)
      .then -> debuggerModel.toggleBreakpoint({scriptUrl, lineNumber: 2})
      .then -> checkBreakpoints(0)

    it 'while disconnected, toggles breakpoints that were set while connected',
    -> waitsForPromise ->
      debuggerModel.connect(wsUrl, onPause, onResume)
      .then -> debuggerModel.toggleBreakpoint({scriptUrl, lineNumber: 2})
      .then -> checkBreakpoints(1)
      .then -> debuggerModel.close()
      .then -> debuggerModel.toggleBreakpoint({scriptUrl, lineNumber: 2})
      .then -> checkBreakpoints(0)
      
