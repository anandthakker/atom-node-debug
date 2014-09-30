url = require 'url'
Q = require 'q'
_ = require 'underscore-plus'
{nodeDebug, nodeInspector} = require './spec-helper'

debug = require('debug')
debug.enable([
  # 'atom-debugger:backend'
  # 'atom-debugger:api'
  'atom-debugger:model'
  # 'atom-debugger:view'
  # 'atom-debugger:package'
].join(','))
debug.log = console.debug.bind(console)


DebuggerApi = require '../lib/debugger-api.coffee'
DebuggerModel = require '../lib/debugger-model.coffee'
RemoteObject = require '../lib/model/remote-object'

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
        debuggerModel = new DebuggerModel({}, new DebuggerApi())
        
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
        

  describe 'pause', ->
    beforeEach ->
      waitsForPromise ->
        debuggerModel.connect(wsUrl, onPause, onResume).then ->
          waitsFor ->
            onPause.callCount > 0

    it 'yields a known script url on the initial pause', ->
      [pauseLoc] = onPause.mostRecentCall.args
      expect(pauseLoc.lineNumber).toBeDefined()
      expect(pauseLoc.scriptUrl).toBe(scriptUrl)

    it 'populates call frame\'s scope chain with RemoteObject wrappers', ->
      frames = debuggerModel.getCallFrames()
      topScope = frames[0].scopeChain[0].object
      expect(topScope?.constructor?.name).toBe 'RemoteObject'
            
    fit 'loads remote object properties and wraps them with' +
    'RemoteObject wrappers as appropriate', ->
      waitsForPromise ->
        debuggerModel.toggleBreakpoint({scriptUrl, lineNumber: 3})
        .then -> debuggerModel.resume()
        .then ->
          waitsFor ->
            onPause.callCount is 2
        .then ->
          frames = debuggerModel.getCallFrames()
          topScope = frames[0].scopeChain[0].object
          topScope.load()
        .then (scope)->
          expect(scope.properties).toBeDefined() #populated
          y = _.find scope.properties, (prop)-> #has 'y' from script
            prop.name is 'y'
          expect(y?.value?.value).toBe(10)
          for prop in scope.properties # child remote objects are wrapped
            if prop.value?.type is 'object'
              expect(prop.value.constructor?.name).toBe 'RemoteObject'

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
      
