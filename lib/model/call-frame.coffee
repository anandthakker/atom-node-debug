debug = require('debug')('atom-debugger:model')
Q = require('q')

RemoteObject = require './remote-object'

module.exports=
class CallFrame
  constructor: (callFrameObject, @api)->
    { @callFrameId,
      @functionName,
      @location,
      @scopeChain} = callFrameObject

    @thisObject = new RemoteObject(callFrameObject['this'])
    @scopeChain.forEach (scope)=>
      scope.object = new RemoteObject(scope.object, @api)
