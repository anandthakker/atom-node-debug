# Atom debugger package

Debug javascript code<sup><a id="ref1" href="#note1">1</a></sup> from right within the editor: set breakpoints, step through code,
inspect variable/expression values<sup><a id="ref2" href="#note2">2</a></sup>.

We all love (and couldn't live without) the Chrome inspector, but sometimes you just don't want
to open up your whole source tree in another browser.

<small>
Notes:
<a id="note1" href="#ref1">1</a></sup> Currently only works using node to run js. Working on a way to connect to a running Chrome browser, too.
<a id="note2" href="#ref2">2</a></sup> Coming soon!
</small>

![](https://raw.githubusercontent.com/anandthakker/atom-node-debug/master/screenshot.gif)

# Features
- Run debugger on current file, or attach to an existing debugger session.
- Step through (over, into, out) node code.
- Rudimentary console output.

# Roadmap

- [ ] Ability to attach to Chrome debugger in addition to Node one. **This will be a challenge,
  but would be HUGE!**
- [x] Open up a new tab when execution leaves current source.
- [x] Persist breakpoints across debugger sessions.
- [ ] TESTS! (Although the underlying API has tests, the ui wiring doesn't.)
- [ ] Breakpoint list
- [ ] Variables
- [ ] Jump up and down the stack
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


# Contributing

Issues and PR's welcome.

# Thanks

- [node-inspector][1]
- [chromium][2]

# License

[MIT][3]


[1]:https://github.com/node-inspector/node-inspector
[2]:http://chromium.org
[3]:https://github.com/anandthakker/atom-node-debug/blob/master/LICENSE.md
