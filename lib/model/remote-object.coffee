debug = require('debug')('atom-debugger:model')
Q = require('q')

module.exports=
class RemoteObject
  constructor: ({
    @className,
    @description,
    @objectId,
    @subType,
    @type
    @value}, @api)->

  # load the remote object's properties from the api and return a promise
  # for the populated object.
  load: ->
    return Q() if @loaded
    Q.ninvoke @api.runtime, 'getProperties', @objectId, false
    .then ([@properties])=>
      for prop in @properties
        if prop.value?.type is 'object'
          prop.value = new RemoteObject(prop.value, @api)

      @loaded = true
      debug('remote object loaded', this)
      this
