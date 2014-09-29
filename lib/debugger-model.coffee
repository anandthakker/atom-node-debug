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
  connect: (@wsUrl, @onPause, @onResume, @openScript) ->
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
        debug('getResourceTree returned!', err, result)
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
  addScript: (scriptObject)->
    @scriptCache[''+scriptObject.scriptId] = scriptObject
    debug('added script', scriptObject)
    
    # TEMPORARY!  TODO
    @openScript({scriptId: scriptObject.scriptId, lineNumber: 0})
    
    
  clearScripts: () -> @scriptCache = {}
  getScript: (id) -> @scriptCache[''+id]
  getScriptIdForUrl: (url)->
    for id,script of @scriptCache
      if script.sourceURL is url then return id
    return null


  ###
  Breakpoints
  ###
  # array of {breakpointId:id, locations:array of {scriptUrl, lineNumber}}
  breakpoints: []
  
  registerBreakpoints: (breakpoints) ->
    q.all(@breakpoints.map ({breakpointId, locations})->
      q.all(locations.map (location)=>@setBreakpoint(locations))
    )
    
  setBreakpoint: (location)->
    def = q.defer()

    if not @isActive
      @breakpoints.push
        locations: [location]
      def.resolve()
    else
      @api.debugger.setBreakpointByUrl(location.lineNumber, location.scriptUrl,
      (err, breakpointId, locations) =>
        debug('setBreakpointByUrl', err, breakpointId, locations)
        if err then console.error(err)
        @breakpoints.push(
          breakpointId: breakpointId
          locations: locations
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

  getBreakpointsAtLocation: ({scriptUrl, lineNumber}) ->
    scriptId = getScriptIdForUrl(scriptUrl)
    @breakpoints.filter (bp)->
      (scriptId is bp.locations[0].scriptId and
      lineNumber is bp.locations[0].lineNumber)
  getBreakpoints: -> [].concat @breakpoints
  clearAllBreakpoints: ->
    @breakpoints = []
  
  
  ###
  Current (paused) point in execution.
  ###
  currentPause: null
  getCurrentPauseLocations: ->
    (@currentPause?.callFrames ? []).map ({location})->location
  
  ###* @return {scriptId, lineNumber} of current pause. ###
  setCurrentPause: (@currentPause)->@currentPause.callFrames[0].location
  clearCurrentPause: ->
    @currentPause = null
    
