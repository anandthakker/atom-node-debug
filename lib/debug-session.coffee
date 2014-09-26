DebuggerApi = require('debugger-api')

module.exports =
  constructor: (port) ->
    @bug = new DebuggerApi({debugPort: 5000})
    @bug.enable()
  
  close: ->
    @bug.close()
    
  
