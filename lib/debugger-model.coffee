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
    @breakpoints = state?.breakpoints ? []
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
    @openScript ?= ->

    debug('starting debugger', wsUrl)

    @api.connect(wsUrl)
    deferred = q.defer()
    @api.once 'connect', =>
      @isActive = true
      q.all [
        q.ninvoke @api.debugger, 'enable', null
        q.ninvoke @api.page, 'getResourceTree', null
      ]
      .then => @registerCachedBreakpoints()
      .then deferred.resolve
      
    @api.once 'close', => @close()

    @api.on('resumed', =>
      debug('resumed')
      @clearCurrentPause()
      @onResume?()
      return
    )
    @api.on('paused', (breakInfo)=>
      debug('paused')
      @setCurrentPause(breakInfo)
      @onPause(@getCurrentPauseLocations()[0])
      return
    )
    
    @api.on 'scriptParsed', (scriptObject)=>@addScript(scriptObject)

    deferred.promise


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
    if /^http/.test scriptObject.sourceURL
      @openScript({scriptId: scriptObject.scriptId, lineNumber: 0},
        {changeFocus: false})

    
  clearScripts: () -> @scriptCache = {}
  getScript: (id) -> @scriptCache[''+id]

  # TODO: clean this up. Currently, it relies on scriptId defaulting
  # to scriptUrl when the debugger isn't running, which is fragile and
  # stupid.
  getScriptIdForUrl: (url)->
    for id,script of @scriptCache
      if script.sourceURL is url then return id
    return url

  _scriptUrl: (scriptIdOrLocation)->
    if typeof scriptIdOrLocation is 'object'
      scriptIdOrLocation.scriptUrl ? @_scriptUrl(scriptIdOrLocation.scriptId)
    else
      script = @getScript(scriptIdOrLocation)
      @getScript(scriptIdOrLocation)?.sourceURL ? scriptIdOrLocation



  ###
  Breakpoints
  ###
  # array of {breakpointId:id, locations:array of {scriptUrl, lineNumber}}
  breakpoints: []
  registerCachedBreakpoints: () ->
    debug('registering cached breakpoints', @breakpoints)
    breaks = @breakpoints
    @breakpoints = []
    q.all(breaks.map ({breakpointId, locations})=>
      q.all(locations.map (loc)=>
        @setBreakpoint(loc))
    )
    
  setBreakpoint: ({lineNumber, scriptUrl})->
    debug('setBreakpoint', lineNumber, scriptUrl)
    def = q.defer()

    if not @isActive
      @breakpoints.push theBreakpoint=
        locations: [{lineNumber, scriptUrl, scriptId: scriptUrl}]
      def.resolve(theBreakpoint)
    else
      @api.debugger.setBreakpointByUrl(
        lineNumber, scriptUrl,
        (err, breakpointId, locations) =>
          debug('setBreakpointByUrl response', err, breakpointId, locations)
          if err then console.error(err)
          # tag the returned breakpoint locations with scriptUrl
          # so that we'll still know what file it's in when we
          # cache it.
          loc.scriptUrl = @_scriptUrl(loc)  for loc in locations
          # now save it to the list.
          @breakpoints.push theBreakpoint=
            breakpointId: breakpointId
            locations: locations
          def.resolve(theBreakpoint)
        )
      
    def.promise
    
  removeBreakpoint: (id)->
    def = q.defer()
    if @isActive
      @api.debugger.removeBreakpoint(id, -> def.resolve())
    else def.resolve()
    @breakpoints = @breakpoints.filter ({breakpointId})->breakpointId isnt id
    def.promise
  
  toggleBreakpoint: ({scriptUrl, lineNumber})->
    debug('toggleBreakpoint', scriptUrl, lineNumber)
    existing = @getBreakpointsAtLocation({scriptUrl, lineNumber})
    if existing.length > 0
      q.all(@breakpoints.map ({breakpointId})=>@removeBreakpoint(breakpointId))
    else @setBreakpoint({scriptUrl, lineNumber})

  getBreakpointsAtLocation: ({scriptUrl, lineNumber}) ->
    debug('getBreakpointsAtLocation', scriptUrl, lineNumber)
    scriptId = @getScriptIdForUrl(scriptUrl) ? scriptUrl
    @breakpoints.filter (bp)->
      (scriptUrl is bp.locations[0].scriptUrl and
      lineNumber is bp.locations[0].lineNumber)
      
  getBreakpoints: -> [].concat @breakpoints
  
  clearAllBreakpoints: -> @breakpoints = []
  
  
  ###
  Current (paused) point in execution.
  ###
  currentPause: null

  # Get the stack of locations at which we're currently paused.
  # @return [{scriptId, scriptUrl, lineNumber}]
  getCurrentPauseLocations: ->
    (@currentPause?.callFrames ? []).map ({location})->location
  
  ###* @return {scriptId, scriptUrl, lineNumber} of current pause. ###
  setCurrentPause: (@currentPause)->
    @currentPause.callFrames.forEach (cf)=>
      cf.location.scriptUrl = @_scriptUrl(cf.location)
    @currentPause.callFrames[0].location
  clearCurrentPause: ->
    @currentPause = null
    
