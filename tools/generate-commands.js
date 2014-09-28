/*
Adapted from
https://github.com/node-inspector/node-inspector/blob/master/tools/generate-commands.js

Copyright (c) 2011, Danny Coates
All rights reserved.
 Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer. Redistributions in binary
form must reproduce the above copyright notice, this list of conditions and
the following disclaimer in the documentation and/or other materials
provided with the distribution. THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT
HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

/* jshint evil:true */

var fs = require('fs'),
    protocol = require('./protocol.json');

eval(fs.readFileSync('./node_modules/node-inspector/front-end/utilities.js', 'utf8'));
eval(fs.readFileSync('./node_modules/node-inspector/front-end/InspectorBackend.js', 'utf8'));

var commands = InspectorBackendClass._generateCommands(protocol);
var header = '// Auto-generated.\n' +
             '// Run `node tools/generate-commands.js` to update.\n' +
             '\n';

fs.writeFileSync('./lib/register-backend-commands.js',
  header +
  'module.exports = function(InspectorBackend) {\n' +
  commands.replace(/^(InspectorBackend)/gm, '  $1') + //indentation
  '\n};'
  );
