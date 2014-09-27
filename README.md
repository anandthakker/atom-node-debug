# node-debug package

# *PLEASE NOTE*
I just changed the name from `atom-node-debug` to `node-debug`.  Please uninstall
the previous package, or it'll conflict!

Debug node code from right within the editor!

We all love (and couldn't live without) the chrome inspector, but sometimes you just don't want
to open up your whole source tree in another browser.

Uses [node-inspector][1] under the hood, via a thin adapter layer provided by [debugger-api][2].

![](https://raw.githubusercontent.com/anandthakker/atom-node-debug/master/screenshot.gif)

[1]:https://github.com/node-inspector/node-inspector
[2]:https://github.com/anandthakker/debugger-api

# Roadmap

Currently just have step through and breakpoints.  More to come:

- [x] Open up a new tab when execution leaves current source.
- [x] Persist breakpoints across debugger sessions.
- [ ] TESTS! (Although the underlying API has tests, the ui wiring doesn't.)
- [ ] Breakpoint list
- [ ] Variables
- [ ] Jump up and down the stack
- [ ] Eval
- [ ] Save and continue

And plenty more, I'm sure.

# Contributing

Issues and PR's welcome.

# License

MIT
