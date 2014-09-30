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
    # the current list of breakpoints is from before this
    # session. hold them for now, hook 'em up once we've paused.
    breaks = @breakpoints
    @breakpoints = []

    @api.connect(wsUrl)
    
    deferred = q.defer()
    @api.once 'connect', =>
      @isActive = true
      q.all [
        q.ninvoke @api.debugger, 'enable', null
        q.ninvoke @api.page, 'getResourceTree', null
      ]
      .then deferred.resolve
      
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
  getScriptUrlForId: (id)->
    script = @getScript(id)
    @getScript(id)?.sourceURL ? id


  ###
  Breakpoints
  ###
  # array of {breakpointId:id, locations:array of {scriptUrl, lineNumber}}
  breakpoints: []
  
  registerBreakpoints: (breakpoints) ->
    q.all(breakpoints.map ({breakpointId, locations})=>
      q.all(locations.map (loc)=>
        @setBreakpoint(loc))
    )
    
  setBreakpoint: ({lineNumber, scriptUrl})->
    debug('setBreakpoint', location)
    def = q.defer()

    if not @isActive
      @breakpoints.push locations:[{lineNumber, scriptUrl, scriptId: scriptUrl}]
      def.resolve()
    else
      @api.debugger.setBreakpointByUrl(
        lineNumber, scriptUrl,
        (err, breakpointId, locations) =>
          debug('setBreakpointByUrl', err, breakpointId, locations)
          if err then console.error(err)
          # tag the returned breakpoint locations with scriptUrl
          # so that we'll still know what file it's in when we
          # cache it.
          loc.scriptUrl = scriptUrl for loc in locations
          # now save it to the list.
          @breakpoints.push
            breakpointId: breakpointId
            locations: locations
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
    
