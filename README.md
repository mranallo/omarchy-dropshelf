# Omarchy Dropshelf

A persistent floating shelf for Omarchy. Drop files or images onto it, then drag them into Slack, a browser, or any application that accepts file drops.

Dropshelf stores file URI references only. It never moves, copies, or deletes the original files.

## Install

```bash
omarchy plugin add https://github.com/mranallo/omarchy-dropshelf.git --enable
```

The Dropshelf icon is added to the right side of the Omarchy bar. Click it to open the floating shelf.

For a centered floating window, add this rule to `~/.config/hypr/hyprland.lua`:

```lua
o.window({ class = "^org.quickshell$", title = "^Dropshelf$" }, { float = true, center = true, size = { 420, 560 } })
```

## Use

1. Click the shelf icon in the Omarchy bar.
2. Drag local files or images onto the window.
3. Drag a shelf item into Slack or another application.
4. Remove an individual reference with its `x` button, or use **Clear**.

The shelf contents are stored at `$XDG_STATE_HOME/omarchy-dropshelf/shelf.json`, or `~/.local/state/omarchy-dropshelf/shelf.json` when `XDG_STATE_HOME` is unset.

## Development

Validate the plugin and run the model tests:

```bash
omarchy plugin validate .
node tests/model.test.js
```

To install a development checkout, link or copy this directory to:

```text
~/.config/omarchy/plugins/io.github.mranallo.dropshelf
```

Plugin files hot-reload while Omarchy Shell is running.

## License

MIT
