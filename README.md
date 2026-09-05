# Dock

An always-visible application dock for the Omarchy shell.

It reserves its own strip along the bottom edge, the way the bar reserves its
26px at the top. Windows tile above it, so the dock never covers a window and
no window ever covers the dock — which is why it needs none of the autohide
machinery other docks carry.

## Requirements

- Omarchy 4 (the Quickshell-based `omarchy-shell`)
- Hyprland — window matching and focus go through its toplevel list

## Install

```bash
git clone https://github.com/mdespeuilles/omarchy-dock.git \
  ~/.config/omarchy/plugins/mdespeuilles.dock
~/.config/omarchy/plugins/mdespeuilles.dock/install.sh
```

Cloned straight into the plugins folder, `install.sh` has nothing to move: it
only declares the plugin to the shell and enables it. Clone it anywhere else
and the script copies it into place (`--link` symlinks instead, handy to try
but not to develop against — the shell watches the plugins folder without
following links).

To uninstall:

```bash
omarchy plugin disable mdespeuilles.dock
rm -rf ~/.config/omarchy/plugins/mdespeuilles.dock
```

## Behaviour

- **Pinned apps first**, in the order of `pinned` in the config, then a thin
  divider, then every app that is running but not pinned.
- **Left click** — launches the app if it has no window, and Hyprland opens it
  on the workspace you are looking at. If it already has windows, the click
  raises one; clicking again raises the next, so a two-window app takes two
  clicks to walk rather than raising the same window twice.
- **Middle click** — always a new instance, even when the app is already open.
- **Right click** — New window / Pin to dock / Unpin from dock / Quit. Quit
  closes every window of the app, so it says how many when there is more than
  one.
- **Indicator dots** under a running app: one per window, up to three. The dot
  is accented and elongated while one of that app's windows is focused, so the
  dock shows both how many windows there are and whether you are in one.

Everything is theme-driven: colors, corner radius and spacing come from the
shell's `Color` and `Style` singletons, so `omarchy theme set <name>` restyles
the dock with no configuration of its own.

## The application grid

The nine-dot button at the left of the dock opens a full-screen grid of every
installed application.

- **Type** to search — no need to click a field first. The matching, scoring and
  sorting are `appLibrary.sortedEntries`, the same search the Omarchy menu uses.
- **Arrows** move, **Enter** launches, **Esc** clears the search and then closes.
- **Left click** launches and closes the panel.
- **Right click** opens Launch / Pin to dock / Unpin from dock.
- A small accent dot on a tile means the app is already on the dock.

`omarchy-shell dock apps` toggles it, so it can take a keybinding of its own.

Two details this panel had to get right:

`sortedEntries` returns **scoring rows** — `{ entry, score, key, name }` — not
desktop entries, and its `name` is lowercased for sorting. Reading `.icon` and
`.name` off a row gives you no icon and a lowercased label; the real entry is in
`.entry`.

Layer-shell keyboard focus is **primed** `Exclusive` then settled to `OnDemand`,
copying `Ui/KeyboardPanel`. Exclusive is the only mode that reliably takes
keyboard focus when the surface maps, but while it is on Hyprland routes every
pointer event to that surface — which fires the outside-click dismissal the
instant the panel appears.

## Settings

**Right-click the nine-dot button.** Left click opens the applications, right
click opens the settings card — the button is the only system slot in a row
that is otherwise all applications, so it is where dock-level actions belong.
`omarchy-shell dock settings` opens the same card, which is also the way back
in after hiding the button.

Every control applies immediately and writes `dock.json`, the same way pinning
does. There is no OK button to forget.

| Setting | What it changes |
|---|---|
| **Applications button** | Shows or hides the nine-dot button, and the divider with it. |
| **Height** | Icon size — Small 32, Medium 40, Large 48, Huge 56 — and with it the height of the whole strip. The card names the resulting reserved height. |

There is deliberately no auto-hide option. One was built and removed: floating
means giving up the reserved strip, which is the one thing this dock exists to
do, and revealing on pointer approach was not pleasant enough to justify it.

## Config

`~/.config/omarchy/dock.json`, written by the dock itself when you pin and
unpin, and hand-editable — it is watched, so a save shows up immediately.

```json
{
  "version": 1,
  "pinned": ["brave-browser", "foot", "org.gnome.Nautilus"],
  "iconSize": 40
}
```

| Key | Default | What it does |
|---|---|---|
| `pinned` | seeded on first run | Desktop entry ids, in dock order. The `.desktop` suffix is optional. |
| `iconSize` | `40` | Icon edge in logical pixels, 16–96. The reserved strip grows with it. |
| `showAppsButton` | `true` | The nine-dot applications button. |

On a first run with no config file, the dock seeds `pinned` from a short
candidate list filtered down to the apps actually installed on the machine, so
it opens with something rather than an empty sliver. Unpin what you don't want.

## Keybindings

The dock registers an IPC target, so pinning and launching work without the
mouse. In `~/.config/hypr/bindings.lua`:

```lua
o.bind("<YOUR KEYBIND>", "Focus or launch the browser", "omarchy-shell dock launch brave-browser")
```

| Call | Effect |
|---|---|
| `omarchy-shell dock apps` | toggle the application grid |
| `omarchy-shell dock settings` | toggle the settings card |
| `omarchy-shell dock launch <id>` | same as a left click: raise the next window, or launch |
| `omarchy-shell dock pin <id>` | pin an app |
| `omarchy-shell dock unpin <id>` | unpin an app |

## Matching windows to apps

Hyprland's app ids only mostly agree with desktop entry ids — `Brave-browser`
against `brave-browser`, or a WM class against an entry that declares
`StartupWMClass`. Each toplevel is resolved with `DesktopEntries.byId` first
and `heuristicLookup` second; the latter is what knows about those cases, and
is the reason a running window finds its pinned slot instead of appearing a
second time on the right.

## Two things worth knowing

**Hyprland warps the cursor on focus changes** by default, so clicking a dock
icon teleports the pointer onto the window it raised. That is the compositor,
not the dock. `cursor.no_warps = true` in `~/.config/hypr/looknfeel.lua` turns
it off; it applies to every focus change, not just dock clicks, and leaves
`warp_on_change_workspace` alone.

**Quickshell recompiles plugin QML from a cache.** Saving a file logs
`Local plugin changed, reloading` and still runs the old code, which makes an
edit look like it had no effect. `omarchy restart shell` forces a clean reload.
The tell is an error whose line number does not move while the file does.

## Files

| File | What |
|---|---|
| `Dock.qml` | the surface, the slots, the tooltip and the context menu |
| `AppPanel.qml` | the full-screen application grid and its search |
| `SettingsPanel.qml` | the settings card |
| `DockModel.js` | pure model logic: id normalization, the pinned/running merge, window cycling, config parsing |

## License

MIT — see [LICENSE](LICENSE).
