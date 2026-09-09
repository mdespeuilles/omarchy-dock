import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "AppSearch.js" as AppSearch

// The dock's own application library: icon paths, the sorted app list, and
// launching.
//
// This used to be `shell.appLibrary`, and borrowing it was the right call
// while the shell handed it over. It no longer does. Omarchy grants that
// capability only to plugins declaring the "menu" kind, and on this release it
// never arrives at a third-party plugin at all: `shell.appLibrary` stays null
// even for a manifest that declares "menu", and the scoped `shell` handle
// itself is revoked about a second after the panel loads and never
// re-injected. A dock whose icons depend on a capability it cannot hold is a
// dock that breaks on the next upgrade.
//
// So the three things the dock actually wanted come from Quickshell directly,
// which hands them to any QML file and takes nothing back: DesktopEntries for
// the app list, Quickshell.iconPath for the theme lookup, execDetached for the
// launch. Nothing here needs the host's permission.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  // Emitted whenever the visible application set may have changed: entries
  // appeared or vanished, or the hidden-entry filter reloaded.
  signal appsChanged()

  // Maps an icon name to a file on disk ("omacut" -> ".../apps/omacut.svg").
  // Two things need it. Qt's themed lookup caches at process start and never
  // re-scans, so an app installed since then would otherwise draw the generic
  // fallback; and an unconstrained themed lookup can resolve an app name like
  // "zoom" to an action icon, which this index — limited to apps/ and
  // devices/ — cannot.
  property var iconIndex: ({})
  property var pendingIconIndex: ({})

  // Desktop ids the launcher should not offer: omarchy's own hide list plus
  // the entries this desktop is excluded from by OnlyShowIn/NotShowIn.
  property var configuredHiddenIds: ({})
  property var desktopHiddenIds: ({})

  function entryName(entry) {
    return AppSearch.entryName(entry)
  }

  function entrySubtext(entry) {
    return AppSearch.entrySubtext(entry)
  }

  function isHidden(entry) {
    var id = String((entry && entry.id) || "")
    return root.configuredHiddenIds[id] === true || root.desktopHiddenIds[id] === true
  }

  function sortedEntries(query) {
    var values = []
    try {
      values = DesktopEntries.applications.values || []
    } catch (e) {
      values = []
    }
    return AppSearch.sortedEntries(values, query, function (entry) {
      return root.isHidden(entry)
    })
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    // A desktop entry may name a file instead of a theme icon.
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var found = root.iconIndex[value]
    if (found) return Util.fileUrl(found)
    var themed = Quickshell.iconPath(value, true)
    if (themed.length > 0) return themed
    return Quickshell.iconPath("application-x-executable", true)
  }

  // The panel calls this when it opens, so an app installed since the last
  // scan shows its real icon rather than the fallback.
  function refreshIcons() {
    if (!iconIndexScan.running) iconIndexScan.running = true
  }

  function launch(desktopId, name) {
    var id = String(desktopId || "")
    if (!id) return
    // gtk-launch as the resolver handles ids with spaces and entries UWSM
    // rejects; the uwsm-app wrapper puts the app in its own scope under
    // app-graphical.slice instead of inheriting the shell's service. Keep the
    // .desktop suffix or ids like org.telegram.desktop don't resolve.
    Util.execArgv(["uwsm-app", "--", "gtk-launch", id + ".desktop"])
  }

  function normalizeId(id) {
    var value = String(id || "").trim()
    if (value.slice(-8) === ".desktop") value = value.slice(0, -8)
    return value
  }

  function idsFromLines(rawText) {
    var out = ({})
    var lines = String(rawText || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      var id = root.normalizeId(lines[i])
      if (id.length > 0) out[id] = true
    }
    return out
  }

  function iconIndexScanCommand() {
    // List app and device icons across the XDG icon dirs and /usr/share/pixmaps
    // as plain paths. SVGs come before PNGs so the parser, which keeps the
    // first hit per name, prefers the scalable one.
    return [
      'dirs="$HOME/.icons $HOME/.local/share/icons";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
      'for ext in svg png; do',
      '  for base in $dirs; do',
      '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) -name "*.$ext" 2>/dev/null;',
      '  done;',
      '  find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null;',
      'done'
    ].join(' ')
  }

  function indexIconLine(path) {
    var value = String(path || "").trim()
    if (value.length === 0) return
    var slash = value.lastIndexOf("/")
    var file = slash >= 0 ? value.slice(slash + 1) : value
    var dot = file.lastIndexOf(".")
    var name = dot > 0 ? file.slice(0, dot) : file
    if (name.length > 0 && root.pendingIconIndex[name] === undefined)
      root.pendingIconIndex[name] = value
  }

  QtObject {
    id: desktopHiddenOutput
    property string text: ""
  }

  // Both scans run in non-login shells on purpose. A login shell sources the
  // user's profile, and tools like mise touch ~/.local/share on activation —
  // a directory the desktop-entry watcher monitors — so every scan would
  // trigger the next one and pin a core at idle.
  Process {
    id: desktopHiddenScan
    command: ["bash", "-c", Util.shellQuote(root.omarchyPath + "/shell/services/hidden-entries.sh")
      + " " + Util.shellQuote([Quickshell.env("XDG_CURRENT_DESKTOP"),
        Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")]
        .filter(function (v) { return String(v || "").length > 0 }).join(":"))]
    stdout: SplitParser { onRead: function (line) { desktopHiddenOutput.text += line + "\n" } }
    onStarted: desktopHiddenOutput.text = ""
    // A future omarchy may move or drop that script. Losing the filter costs
    // the panel a few entries it should have hidden; it must not cost the dock
    // its icons, so a failed scan just clears the filter.
    onExited: {
      root.desktopHiddenIds = root.idsFromLines(desktopHiddenOutput.text)
      root.appsChanged()
    }
  }

  Process {
    id: iconIndexScan
    command: ["bash", "-c", root.iconIndexScanCommand()]
    stdout: SplitParser { onRead: function (line) { root.indexIconLine(line) } }
    onStarted: root.pendingIconIndex = ({})
    // Swapping the property re-evaluates every iconSource() binding, so newly
    // found icons appear without rebuilding the row.
    onExited: root.iconIndex = root.pendingIconIndex
  }

  // A package install touches many entries at once; coalesce the burst into
  // one rescan.
  Timer {
    id: iconIndexDebounce
    interval: 750
    onTriggered: if (!iconIndexScan.running) iconIndexScan.running = true
  }

  FileView {
    path: root.omarchyPath + "/default/omarchy/launcher.hides"
    watchChanges: true
    printErrors: false
    onLoaded: { root.configuredHiddenIds = root.idsFromLines(text()); root.appsChanged() }
    onFileChanged: { root.configuredHiddenIds = root.idsFromLines(text()); root.appsChanged() }
    onLoadFailed: { root.configuredHiddenIds = ({}); root.appsChanged() }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      desktopHiddenScan.running = true
      iconIndexDebounce.restart()
      root.appsChanged()
    }
  }

  Component.onCompleted: {
    desktopHiddenScan.running = true
    iconIndexScan.running = true
  }
}
