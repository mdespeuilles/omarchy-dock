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
  one. Right-clicking the same icon again closes the menu, right-clicking
  another hands it straight over, and while a menu is up a plain click anywhere
  on the dock dismisses it instead of launching — the same thing a click off the
  dock has always done.
- **Drag a pinned icon** sideways to reorder the dock. The row opens a gap as
  you go, the icon can only travel as far as the pinned apps reach, and the new
  order is written to `dock.json` on the drop — not at every slot it crosses.
  Below the drag threshold the gesture is still a click, so nothing changes
  about clicking. Apps that are only running, past the divider, have no saved
  position and so do not drag.
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
  sorting live in `AppSearch.js`, ranked the way the Omarchy menu ranks: what a
  name starts with beats what it merely contains, and both beat a match in a
  comment or a keyword.
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

**Or right-click the dock itself**, anywhere that is not an icon: the strip's
background, the gap around the row, the divider. That is the way in that
survives hiding the button, so no setting can lock you out of the settings.
`omarchy-shell dock settings` opens the same card.

Every control applies immediately and writes `dock.json`, the same way pinning
does. There is no OK button to forget.

| Setting | What it changes |
|---|---|
| **Applications button** | Shows or hides the nine-dot button, and the divider with it. Right-clicking the dock background still opens this card. |
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
| `pinned` | seeded on first run | Desktop entry ids, in dock order — the order a drag rewrites. The `.desktop` suffix is optional. |
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

**The dock owns its application library.** It used to read icons, the app list
and launching from `shell.appLibrary`, the host object the shell injects into a
plugin. Omarchy now scopes that object to plugins declaring the `menu` kind,
and as of Omarchy 4 it never reaches a third-party plugin at all: `appLibrary`
arrives null even for a manifest that declares `menu`, and the injected `shell`
handle itself is revoked about a second after load and never replaced. So
`DockAppLibrary.qml` reads `DesktopEntries`, `Quickshell.iconPath` and
`execDetached` directly — all of which Quickshell gives any QML file. Nothing
in the dock depends on `shell` any more; treat that property as always about to
go null.

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
| `DockModel.js` | pure model logic: id normalization, the pinned/running merge, window cycling, reordering, config parsing |
| `DockAppLibrary.qml` | icon paths, the installed-app list and launching, read straight from Quickshell |
| `AppSearch.js` | pure search logic: scoring and ordering for the grid's filter |

## License

MIT — see [LICENSE](LICENSE).
