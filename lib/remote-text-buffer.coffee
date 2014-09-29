url = require('url')

debug = require('debug')('atom-debugger:package')
TextBuffer = require 'text-buffer'
request = require 'request'
_ = require 'underscore-plus'
Q = require 'q'

# Subclass of `TextBuffer` that represents a buffer of text pulled from a
# remote source.
#
# TODO: RemoteTextBuffer doesn't serialize well
# TODO: Remote script opening needs to check for existing first.
module.exports=
class RemoteTextBuffer extends TextBuffer
  
  # For use in registering an opener on the workspace. Calling this will open
  # up an `Editor` backed by one of these `RemoteTextBuffer`s, the same way
  # workspace.open() would have for a file path.
  @open: (uri, opts)->
    buffer = new RemoteTextBuffer({remoteUri: uri})

    # The following is basically what happens in atom.project.open().
    # It's not pretty, but will suffice till there's a more flexible API.
    atom.project.addBuffer(buffer)
    buffer.load()
      .then((buffer) -> buffer)
      .catch((err)->
        console.error err.stack()
        atom.project.removeBuffer(buffer))

    # because we don't have access to the TextEditor class (UGLY)
    editor = atom.project.buildEditorForBuffer(buffer, opts)

    editor
  
  constructor: ({@remoteUri})->
    super({})
    
  # Prevent the Pane from serializing us (a hack for now, because, being in a
  # package, this class can't register itself with the deserializer before atom
  # tries to deserialize the workspace).
  serialize: null


  updateCachedDiskContentsSync: ->
    throw new Error('Unimplemented: updateCachedDiskContentsSync')
  
  updateCachedDiskContents: ->
    if @loaded then return # don't request more than once.
    debug('requesting', @remoteUri)
    Q.nfcall(request, @remoteUri).then ([response, body])=>
      debug('got response', response)
      # TODO: grab content type from header and use it to set the language
      @cachedDiskContents = body

  isModified: ->
    return false unless @loaded
    @getText() != @cachedDiskContents
    
  getRemoteUri: -> @remoteUri
