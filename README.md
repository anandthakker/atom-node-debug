
# DEPRECATED

This package is no longer under active development.  Please see this very similar (and active) one: https://github.com/kiddkai/atom-node-debugger  (atom package: https://atom.io/packages/node-debugger)


# Atom debugger package

Debug javascript code from right within the editor: set breakpoints, step through code,
inspect variables values.

We all love (and couldn't live without) the Chrome inspector, but sometimes you just don't want
to open up your whole source tree in another browser.

![](https://raw.githubusercontent.com/anandthakker/atom-node-debug/master/screenshot.gif)

# Features
- Step through (over, into, out) node code.
- Navigate the call stack.
- Inspect variable values.
- Rudimentary console output.
- Run debugger on current file, or attach to an existing `node --debug` session.
- Attach to a `Chrome --remote-debugging-port` session to debug javascript running
  in the browser.

# Roadmap

- [x] Ability to attach to Chrome debugger in addition to Node one.
  - [ ] Follow-up: intelligently open *local* source files from current project, even
        when they're being served via http.
- [x] Open up a new tab when execution leaves current source.
- [x] Persist breakpoints across debugger sessions.
- [ ] Breakpoint list
- [x] Variables
- [ ] Structured console messages
- [x] TESTS! (Although the underlying API has tests, the ui wiring doesn't.)
- [x] Jump up and down the stack
- [ ] Eval
- [ ] Save and continue
- [ ] Source maps (a.k.a. coffeescript support)

# Theme/Style

Take a look at [the stylesheet](/stylesheets/atom-node-debug.less).

Haven't yet tested this on anything but the basic
theme, but heads up: it uses `darken()` to modify
theme background color variables for use as breakpoint
and current line markers.  That means the default styles
probably work fine for dark themes, and less well for
light ones.

# Advanced Usage

## Arbitrary Node Inspectors

```bash
$ node-inspector
Node Inspector v0.7.4
Visit http://127.0.0.1:8080/debug?port=5858 to start debugging.
```

You want the *front end* port--8080 in the example above.


## Chrome
**IN ALPHA**

```bash
$ Google\\ Chrome\\ Canary --remote-debugging-port=9222
$ curl http://localhost:9222/json
```
```json
[ {
   "description": "",
   "devtoolsFrontendUrl": "/devtools/devtools.html?ws=localhost:9222/devtools/
   page/4649D7AA-4AAC-4B2E-A86A-A3789FB3EC61",
   "faviconUrl": "https://www.google.com/favicon.ico",
   "id": "4649D7AA-4AAC-4B2E-A86A-A3789FB3EC61",
   "title": "My Web Page!",
   "type": "page",
   "url": "http://mywebpage.com",
   "webSocketDebuggerUrl":"ws://localhost:9222/devtools/page/4649D7AA-4AAC-4B2E-A86A-A3789FB3EC61"
}, ... ]
```

Coppy the `webSocketDebuggerUrl` starting with `ws://...`.

Then use cmd-shift-P 'Debugger:Connect' (ctrl-opt-cmd-I by default) and paste in
the web socket url you just copied.

Once the debugger connects, it'll grab source files from Chrome and open them in
the editor.  Set breakpoints and reload the page to debug!


# Contributing

Issues and PRs welcome.

# Thanks

- [node-inspector][1]
- [chromium][2]

# License

[MIT][3]


[1]:https://github.com/node-inspector/node-inspector
[2]:http://chromium.org
[3]:https://github.com/anandthakker/atom-node-debug/blob/master/LICENSE.md
