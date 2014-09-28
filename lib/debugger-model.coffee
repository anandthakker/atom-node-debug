path = require('path')
url = require('url')

q = require('q')
_ = require('underscore-plus')
debug = require('debug')('atom-debugger:model')

DebuggerApi = require('./debugger-api')

###
Data & control for a debugging scenario and a particular session
Scenario = stuff not tied to an active debugging session:
  - breakpoints
  - watch expressions
Session =
  - url of debugger
  - current execution pointer
    - call frames
    - reason
    - etc
    
  - onPause, onResume callbacks
  
Could distinguish these into two if/when things get complicated.


TODO: Respond to console output!

###
module.exports=
class DebuggerModel
  constructor: (state)->
    @breakpoints = state.breakpoints ? []
    @api = new DebuggerApi()
    
  serialize: ->
    breakpoints: @breakpoints
    
  stepInto: => @api.debugger.stepInto()
  stepOver: => @api.debugger.stepOver()
  stepOut: => @api.debugger.stepOut()
  resume: => @api.debugger.resume()
    
  isActive: false
  connect: (@wsUrl, @onPause, @onResume) ->
    if @isActive then throw new Error('Already connected.')
    @onPause ?= ->
    @onResume ?= ->

    debug('starting debugger', wsUrl)
    # the current list of breakpoints is from before this
    # session. hold them for now, hook 'em up once we've paused.
    breaks = @breakpoints
    @breakpoints = []

    @api.connect(wsUrl)

    @api.once 'connect', =>
      @isActive = true
      @api.debugger.enable(null, (err, result)->
        debug('enabled returned', err, result)
        if(err) then console.error err
        else debug('debugger enabled')
      )
      @api.page.getResourceTree(null, (err, result)->
        debug('getResourceTree returned!', err)
      )
      
    @api.once 'close', => @close()

    @api.on('resumed', =>
      debug('resumed')
      @clearCurrentPause()
      atom.workspaceView.removeClass('debugger--paused')
      @onResume?()
      return
    )
    @api.on('paused', (breakInfo)=>
      debug('paused')

      atom.workspaceView.addClass('debugger--paused')
      @setCurrentPause(breakInfo)

      # this means we're paused for the first time in a new session.
      # TODO: we're using the first pause as a chance to set breakpoints, but
      # this isn't gonna work if we're not able to set debug-brk.
      if breaks?.length > 0
        @registerBreakpoints breaks
        .then => @onPause(@getCurrentPauseLocations()[0])
        breaks = null
      else
        @onPause(@getCurrentPauseLocations()[0])

      return
    )
    
    @api.on 'scriptParsed', (scriptObject)=>@addScript(scriptObject)


  close: ->
    @isActive = false
    @api.close()
    @clearCurrentPause()
    @clearScripts()
    @onResume = null
    @onPause = null

  ###
  Scripts
  ###
  scriptCache: {}
  urlToPath: (earl)-> url.parse(earl).pathname
  addScript: (scriptObject)->
    scriptObject.scriptPath = @urlToPath(scriptObject.sourceURL)
    @scriptCache[scriptObject.scriptId] = scriptObject
  clearScripts: () -> scriptCache = {}
  getScript: (id) -> scriptCache[id]
  getScriptIdForPath: (path)->
    for id,script of scriptCache
      if script.scriptPath is path then return id
    return null
  addPathToLocationObject: ({lineNumber, scriptId}) ->
    scriptUrl = @scriptCache[scriptId]?.sourceURL
    path = if scriptUrl? then @urlToPath(scriptUrl) else ''
    debug('script id -> url -> path', scriptId, scriptUrl, path)
    scriptId: scriptId
    scriptPath: path
    lineNumber: lineNumber

  
  ###
  Breakpoints
  ###
  # array of {breakpointId:id, locations:array of {scriptPath, lineNumber}}
  breakpoints: []
  
  registerBreakpoints: (breakpoints) ->
    q.all(@breakpoints.map ({breakpointId, locations})->
      q.all(locations.map (location)=>@setBreakpoint(locations))
    )
    
  setBreakpoint: (location)->
    def = q.defer()
    
    scriptUrl = url.format
      protocol: 'file'
      pathname: location.scriptPath
      slashes: true

    if not @isActive
      @breakpoints.push
        locations: [location]
      def.resolve()
    else
      @api.debugger.setBreakpointByUrl(location.lineNumber, scriptUrl,
      (err, breakpointId, locations) =>
        debug('setBreakpointByUrl', err, breakpointId, locations)
        if err then console.error(err)
        @breakpoints.push(
          breakpointId: breakpointId
          locations: locations.map (loc)=>@addPathToLocationObject(loc)
        )
        def.resolve()
      )
      
    def.promise
    
  removeBreakpoint: (id)->
    def = q.defer()
    if @isActive
      @api.debugger.removeBreakpoint(id, -> def.resolve())
    else def.resolve()
    @breakpoints = @breakpoints.filter ({breakpointId})->breakpointId isnt id
    def.promise
  
  toggleBreakpoint: (location)->
    existing = @getBreakpointsAtLocation(location)
    if existing.length > 0
      q.all(@breakpoints.map ({breakpointId})=>@removeBreakpoint(breakpointId))
    else @setBreakpoint(location)

  getBreakpointsAtLocation: ({scriptPath, lineNumber}) ->
    @breakpoints.filter (bp)->
      (scriptPath is bp.locations[0].scriptPath and
      lineNumber is bp.locations[0].lineNumber)
  getBreakpoints: -> [].concat @breakpoints
  clearAllBreakpoints: ->
    @breakpoints = []
  
  
  ###
  Current (paused) point in execution.
  ###
  currentPause: null
  getCurrentPauseLocations: ->
    (@currentPause?.callFrames ? []).map ({location})=>
      @addPathToLocationObject(location)
  
  ###* @return {scriptPath, lineNumber} of current pause. ###
  setCurrentPause: (@currentPause)->
    @addPathToLocationObject(@currentPause.callFrames[0].location)
  clearCurrentPause: ->
    @currentPause = null
    
