import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel

// An always-visible application dock along the bottom edge.
//
// It reserves its own strip the way the bar reserves its 26px at the top:
// windows tile above it, so the dock never covers a window and no window ever
// covers the dock. That is the whole reason it can skip the autohide machinery
// other docks need.
//
// Colors, radii and spacing come from the Color and Style singletons, so
// `omarchy theme set` restyles the dock with no code of ours involved. Window
// state is the Wayland toplevel list, which is also what the bar's
// active-window widget reads.
//
// Icons, the app list and launching used to come from `shell.appLibrary`.
// They now come from DockAppLibrary, which reads Quickshell directly: the
// shell no longer lets a third-party plugin hold that capability. The `shell`
// handle below is still injected, and still goes null a moment later, so
// nothing may depend on it.
Item {
  id: root

  // Injected by the shell's panel loader.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property var appLibrary: dockAppLibrary
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/dock.json"

  DockAppLibrary {
    id: dockAppLibrary
    omarchyPath: root.omarchyPath
  }

  // ------------------------------------------------------------- config

  property var pinned: []
  property int iconSize: 40
  property bool showAppsButton: true
  // Seeding is a first-run act, not a fallback. Every save is an atomic
  // write-then-rename with the watcher live, so a reload can fail on a file
  // that exists and is fine; re-seeding there would hand the user back the
  // apps they just unpinned.
  property bool configLoaded: false

  // Seeds for a first run. Only the ids that resolve to an installed desktop
  // entry are kept, so the dock opens with the apps this machine actually has
  // rather than a row of blanks.
  readonly property var seedCandidates: [
    "chromium", "brave-browser", "firefox", "google-chrome",
    "Alacritty", "foot", "kitty", "com.mitchellh.ghostty",
    "org.gnome.Nautilus", "nautilus",
    "obsidian", "code", "spotify", "signal-desktop"
  ]

  // ------------------------------------------------------------ geometry

  readonly property int slotPadding: Style.space(6)
  readonly property int slotSize: root.iconSize + root.slotPadding * 2
  readonly property int indicatorRow: Style.space(7)
  readonly property int panelPadding: Style.space(5)
  readonly property int panelHeight: root.slotSize + root.indicatorRow + root.panelPadding * 2
  readonly property int outerMargin: Style.space(6)
  // What the compositor is asked to keep clear.
  readonly property int reservedHeight: root.panelHeight + root.outerMargin

  // ------------------------------------------------------- window state

  readonly property var activeToplevel: ToplevelManager.activeToplevel
  property var items: []

  // How many slots at the head of the row are pinned, which is how far a drag
  // is allowed to travel.
  readonly property int pinnedCount: {
    var n = 0
    for (var i = 0; i < root.items.length; i++)
      if (root.items[i].pinned === true) n++
    return n
  }

  // The drawn row: the items, with a separator marker inserted where the
  // pinned apps end and the merely-running ones begin.
  readonly property var rows: {
    var out = []
    var sep = DockModel.separatorIndex(root.items)
    for (var i = 0; i < root.items.length; i++) {
      if (i === sep) out.push({ separator: true, item: null })
      out.push({ separator: false, item: root.items[i] })
    }
    return out
  }

  // Hyprland reports app ids that only mostly match desktop ids — "Brave-browser"
  // for "brave-browser", a WM class for an entry that declares StartupWMClass.
  // byId is the fast exact path; heuristicLookup is the one that knows about
  // those, and is the reason a running app finds its pinned slot at all.
  function resolveEntry(appId) {
    var id = DockModel.normalizeId(appId)
    if (id.length === 0) return null
    try {
      var exact = DesktopEntries.byId(id)
      if (exact) return exact
    } catch (e) {}
    try {
      var found = DesktopEntries.heuristicLookup(id)
      if (found) return found
    } catch (e2) {}
    return null
  }

  function rebuild() {
    // A window opening or closing mid-gesture would rebuild the row and destroy
    // the very delegate the drag is running in — the model is a plain array, so
    // every delegate is recreated. The rebuild waits for the drop; a drag lasts
    // a moment, and finishDrag always runs it.
    if (root.dragging) {
      root.rebuildDeferred = true
      return
    }

    var groups = ({})
    var values = []
    try {
      values = ToplevelManager.toplevels.values || []
    } catch (e) {
      values = []
    }

    for (var i = 0; i < values.length; i++) {
      var tl = values[i]
      if (!tl) continue
      var appId = String(tl.appId || "")
      if (appId.length === 0) continue

      var entry = root.resolveEntry(appId)
      var id = DockModel.normalizeId(entry ? entry.id : appId)
      var key = id.toLowerCase()

      if (!groups[key]) {
        groups[key] = {
          id: id,
          name: (entry && entry.name) || appId,
          icon: (entry && entry.icon) || appId,
          toplevels: []
        }
      }
      groups[key].toplevels.push(tl)
    }

    root.items = DockModel.buildItems(root.pinned, groups, function (id) {
      return root.resolveEntry(id)
    })
  }

  function applyConfig(raw) {
    var parsed = DockModel.parseConfig(raw, {
      pinned: root.pinned,
      iconSize: root.iconSize,
      showAppsButton: root.showAppsButton
    })
    root.pinned = parsed.pinned
    root.iconSize = parsed.iconSize
    root.showAppsButton = parsed.showAppsButton
    root.configLoaded = true
    root.rebuild()
  }

  function seedConfig() {
    var seeded = []
    for (var i = 0; i < root.seedCandidates.length; i++) {
      var entry = root.resolveEntry(root.seedCandidates[i])
      if (entry && !DockModel.isPinned(seeded, entry.id))
        seeded.push(DockModel.normalizeId(entry.id))
    }
    root.pinned = seeded
    root.rebuild()
    root.saveConfig()
  }

  function saveConfig() {
    configFile.setText(JSON.stringify({
      version: 1,
      pinned: root.pinned,
      iconSize: root.iconSize,
      showAppsButton: root.showAppsButton
    }, null, 2) + "\n")
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyConfig(text())
    onLoadFailed: if (!root.configLoaded) root.seedConfig()
    onFileChanged: reload()
  }

  // The toplevel list churns on every window open, close and title change;
  // rebuilding is cheap but there is no reason to do it twice for one event.
  Timer {
    id: rebuildDebounce
    interval: 16
    onTriggered: root.rebuild()
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { rebuildDebounce.restart() }
  }

  // A newly installed app can change how an existing app id resolves, so the
  // dock re-reads the entry list rather than caching the lookup.
  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { rebuildDebounce.restart() }
  }

  Component.onCompleted: root.rebuild()

  // ------------------------------------------------------------- actions

  function launch(item) {
    if (!item) return
    root.appLibrary.launch(item.id, item.name)
  }

  // Not running: launch, and Hyprland puts the window on the workspace you are
  // looking at. Running: raise a window — the next one each time, so clicking a
  // two-window app twice gets you both rather than the same one twice.
  function activateOrLaunch(item) {
    if (!item) return
    if (!item.toplevels || item.toplevels.length === 0) {
      root.launch(item)
      return
    }
    var next = DockModel.nextToplevel(item.toplevels, root.activeToplevel)
    if (next) next.activate()
  }

  function quitApp(item) {
    if (!item || !item.toplevels) return
    // Copy first: closing mutates the list this loop walks.
    var windows = item.toplevels.slice()
    for (var i = 0; i < windows.length; i++) windows[i].close()
  }

  // --------------------------------------------------------------- dragging

  // Dragging a pinned icon reorders the row. The reorder is a preview until the
  // button comes up: `pinned` — and with it dock.json — is written once, on the
  // drop, not at every slot the icon crosses. Until then the model holds still
  // and the row shows the new order by sliding the icons the drag has passed.
  property string dragKey: ""
  property int dragFrom: -1
  property int dragTo: -1
  property real dragOffsetX: 0
  property bool rebuildDeferred: false
  readonly property bool dragging: root.dragKey !== ""

  function beginDrag(item, index) {
    if (!item || index < 0) return
    root.dragKey = item.key
    root.dragFrom = index
    root.dragTo = index
    root.dragOffsetX = 0
    root.closeMenu()
  }

  // How far the slot at `pinnedIndex` slides to open the gap: one slot towards
  // the dragged icon's origin, for every slot between where it started and
  // where it is now.
  function dragShift(pinnedIndex) {
    if (!root.dragging || pinnedIndex < 0 || pinnedIndex === root.dragFrom) return 0
    if (root.dragTo > root.dragFrom && pinnedIndex > root.dragFrom && pinnedIndex <= root.dragTo) return -1
    if (root.dragTo < root.dragFrom && pinnedIndex >= root.dragTo && pinnedIndex < root.dragFrom) return 1
    return 0
  }

  // Commit on a drop, discard on a cancel — either way the drag state goes
  // first, so the rebuild at the end is the one that runs for real.
  function finishDrag(commit) {
    var from = root.dragFrom
    var to = root.dragTo
    root.dragKey = ""
    root.dragFrom = -1
    root.dragTo = -1
    root.dragOffsetX = 0
    root.rebuildDeferred = false
    if (commit && from >= 0 && to >= 0 && from !== to) {
      root.pinned = DockModel.moveEntry(DockModel.pinnedOrder(root.items), from, to)
      root.saveConfig()
    }
    root.rebuild()
  }

  function togglePinById(desktopId) {
    var id = DockModel.normalizeId(desktopId)
    if (id.length === 0) return
    root.pinned = DockModel.isPinned(root.pinned, id)
      ? DockModel.withoutPin(root.pinned, id)
      : DockModel.withPin(root.pinned, id)
    root.saveConfig()
    root.rebuild()
  }

  function togglePin(item) {
    if (!item) return
    root.togglePinById(item.id)
  }

  function toggleAppPanel() {
    root.closeMenu()
    appPanel.toggle()
  }

  function toggleSettings() {
    root.closeMenu()
    settingsPanel.toggle()
  }

  SettingsPanel {
    id: settingsPanel

    showAppsButton: root.showAppsButton
    iconSize: root.iconSize
    stripHeight: root.reservedHeight

    onRequestShowAppsButton: function (value) { root.showAppsButton = value; root.saveConfig() }
    onRequestIconSize: function (value) { root.iconSize = value; root.saveConfig() }
  }

  // The grid of every installed application, opened by the dock's leading
  // button. It owns search and its own right-click menu; the dock only has to
  // say what launching and pinning mean.
  AppPanel {
    id: appPanel

    appLibrary: root.appLibrary
    pinnedIds: root.pinned

    onLaunchRequested: function (desktopId, name) {
      root.launch({ id: desktopId, name: name })
    }
    onPinToggleRequested: function (desktopId) {
      root.togglePinById(desktopId)
    }
  }

  // ------------------------------------------------------ popup plumbing

  property var hoverTarget: null
  property string hoverText: ""

  property var menuTarget: null
  property var menuItem: null
  property bool menuOpen: false
  // The menu's rows and title are snapshotted when it opens rather than derived
  // from menuItem. A derived model is rebuilt the moment closing clears
  // menuItem, which destroys the very delegate whose click handler is still
  // running — and takes its `modelData` with it.
  property var menuRows: []
  property string menuTitle: ""

  function targetWindow(target) {
    return target && target.QsWindow ? target.QsWindow.window : null
  }

  function targetBelongsToWindow(target, window) {
    return !!target && !!window && root.targetWindow(target) === window
  }

  function showTooltip(target, text) {
    root.hoverTarget = target
    root.hoverText = String(text || "")
  }

  function hideTooltip(target) {
    if (root.hoverTarget !== target) return
    root.hoverTarget = null
    root.hoverText = ""
  }

  // Right clicking the slot whose menu is already up closes it: the gesture
  // that opened the menu is the one that takes it away.
  function toggleMenu(target, item) {
    if (root.menuOpen && root.menuTarget === target) root.closeMenu()
    else root.openMenu(target, item)
  }

  function openMenu(target, item) {
    if (!item) return
    var windows = item.toplevels ? item.toplevels.length : 0
    root.menuTarget = target
    root.menuItem = item
    root.menuTitle = String(item.name || item.id)
    root.menuRows = [
      { key: "new", label: "New window", shown: true },
      {
        key: "pin",
        label: DockModel.isPinned(root.pinned, item.id) ? "Unpin from dock" : "Pin to dock",
        shown: true
      },
      {
        key: "quit",
        // Quitting closes every window of the app, so the count is in the
        // label rather than a surprise.
        label: windows > 1 ? "Quit (" + windows + " windows)" : "Quit",
        shown: windows > 0
      }
    ]
    root.menuOpen = true
    root.hideTooltip(target)
  }

  // menuRows and menuTitle are deliberately left alone: they are what keeps the
  // delegate alive long enough for its handler to finish.
  function closeMenu() {
    root.menuOpen = false
    root.menuTarget = null
    root.menuItem = null
  }

  // ------------------------------------------------------------- surface

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: dockWindow

        required property var modelData
        screen: modelData

        anchors {
          bottom: true
          left: true
          right: true
        }

        implicitHeight: root.reservedHeight
        // Auto is what makes this a reserved strip rather than an overlay:
        // Hyprland shrinks the tiling area by implicitHeight on this edge.
        exclusionMode: ExclusionMode.Auto

        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "omarchy-dock"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // The dock's own background is a right-click target: settings. It is
        // declared before the panel so every icon on top of it wins the click,
        // and it covers the whole reserved strip rather than just the rounded
        // surface — that is what keeps a way in when the applications button,
        // the other way in, has been switched off.
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.RightButton
          onClicked: {
            // With a menu up, the first click is a dismissal like any other.
            if (root.menuOpen) root.closeMenu()
            else root.toggleSettings()
          }
        }

        BorderSurface {
          id: dockPanel

          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: root.outerMargin

          implicitWidth: Math.max(root.slotSize, dockRow.implicitWidth + root.panelPadding * 2)
          implicitHeight: root.panelHeight
          radius: Style.cornerRadius
          color: Color.popups.background
          borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, 1)

          Row {
            id: dockRow
            anchors.centerIn: parent
            spacing: Style.spacing.xxs

            // Leading "all applications" button. Drawn rather than themed from
            // an icon file: a nine-dot grid in the panel's own text color
            // follows the theme with nothing to ship or look up.
            Item {
              id: appsSlot

              visible: root.showAppsButton
              width: visible ? root.slotSize : 0
              height: root.slotSize + root.indicatorRow

              Rectangle {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.slotSize
                height: root.slotSize
                radius: Math.max(Style.space(6), root.slotSize * 0.22)
                color: appPanel.opened ? Style.selectedFill
                  : (appsMouse.containsMouse ? Style.hoverFill : "transparent")

                Behavior on color {
                  ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
                }

                Grid {
                  anchors.centerIn: parent
                  columns: 3
                  spacing: Math.max(Style.space(2), Math.round(root.iconSize * 0.115))

                  Repeater {
                    model: 9

                    delegate: Rectangle {
                      // Sized well under the app icons: nine solid dots read as
                      // heavier than a glyph of the same bounding box.
                      width: Math.max(Style.space(3), Math.round(root.iconSize * 0.145))
                      height: width
                      radius: width / 2
                      color: Color.popups.text
                      opacity: appsMouse.containsMouse || appPanel.opened ? 1.0 : 0.75
                    }
                  }
                }
              }

              MouseArea {
                id: appsMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function (mouse) {
                  if (mouse.button === Qt.RightButton) root.toggleSettings()
                  else root.toggleAppPanel()
                }
                onEntered: root.showTooltip(appsSlot, "Applications · right click for settings")
                onExited: root.hideTooltip(appsSlot)
                Component.onDestruction: root.hideTooltip(appsSlot)
              }
            }

            // Divider between the button and the apps themselves. Nothing to
            // divide when the dock is empty, so it collapses.
            Item {
              visible: root.showAppsButton && root.rows.length > 0
              width: visible ? Style.space(11) : 0
              height: root.slotSize + root.indicatorRow

              Rectangle {
                anchors.centerIn: parent
                width: Math.max(1, Style.space(1))
                height: Math.round(root.slotSize * 0.5)
                radius: width / 2
                color: Util.alpha(Color.popups.text, 0.22)
              }
            }

            Repeater {
              model: root.rows

              delegate: Item {
                id: slot

                required property var modelData
                required property int index

                readonly property bool isSeparator: modelData.separator === true
                readonly property var item: modelData.item
                readonly property int windowCount: slot.item && slot.item.toplevels ? slot.item.toplevels.length : 0
                readonly property bool running: slot.windowCount > 0
                readonly property bool focused: {
                  if (!slot.running || !root.activeToplevel) return false
                  for (var i = 0; i < slot.item.toplevels.length; i++)
                    if (slot.item.toplevels[i] === root.activeToplevel) return true
                  return false
                }
                readonly property bool menuOpenHere: root.menuOpen && root.menuTarget === slot

                // Pinned items are the head of the row and the separator goes
                // in after them, so a pinned slot's index in the row is also
                // its index in the pinned order. Unpinned slots get -1: they
                // have no saved position to drag.
                readonly property int pinnedIndex: (!slot.isSeparator && slot.item
                  && slot.item.pinned === true) ? slot.index : -1
                readonly property bool dragging: root.dragging && slot.pinnedIndex === root.dragFrom
                readonly property real slideX: slot.dragging
                  ? 0
                  : root.dragShift(slot.pinnedIndex) * (root.slotSize + dockRow.spacing)

                width: slot.isSeparator ? Style.space(11) : root.slotSize
                height: root.slotSize + root.indicatorRow
                // Above its neighbours while it is the one in hand.
                z: slot.dragging ? 1 : 0

                // Both offsets are transforms rather than changes to x: the Row
                // owns x, and a transform moves the icon and its dots together
                // without the positioner arguing about it.
                transform: [
                  Translate {
                    // Neighbours opening the gap. Animated — this one is the
                    // row rearranging itself, not the hand.
                    x: slot.slideX
                    Behavior on x {
                      NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }
                  },
                  Translate {
                    // The icon in hand, tracking the pointer 1:1 and lifted a
                    // little so it reads as picked up.
                    x: slot.dragging ? root.dragOffsetX : 0
                    y: slot.dragging ? -Style.space(4) : 0
                    Behavior on y {
                      NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                  }
                ]

                // Divider between the pinned apps and the ones that are merely
                // running: the dock says which is which without a label.
                Rectangle {
                  visible: slot.isSeparator
                  anchors.centerIn: parent
                  width: Math.max(1, Style.space(1))
                  height: Math.round(root.slotSize * 0.5)
                  radius: width / 2
                  color: Util.alpha(Color.popups.text, 0.22)
                }

                Rectangle {
                  id: slotFill
                  visible: !slot.isSeparator
                  anchors.top: parent.top
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: root.slotSize
                  height: root.slotSize
                  radius: Math.max(Style.space(6), root.slotSize * 0.22)
                  color: slot.menuOpenHere ? Style.selectedFill
                    : (slotMouse.containsMouse ? Style.hoverFill : "transparent")

                  Behavior on color {
                    ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
                  }

                  Image {
                    anchors.centerIn: parent
                    width: root.iconSize
                    height: root.iconSize
                    source: slot.item && root.appLibrary ? root.appLibrary.iconSource(slot.item.icon) : ""
                    // Retina-ish source so the icon stays crisp while the slot
                    // scales on press.
                    sourceSize.width: root.iconSize * 2
                    sourceSize.height: root.iconSize * 2
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    mipmap: true

                    scale: slot.dragging ? 1.06 : (slotMouse.pressed ? 0.88 : 1.0)
                    Behavior on scale {
                      NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                    }
                  }
                }

                // One dot per window, up to three. The focused window's dot is
                // the accented one, so the dock shows both "how many" and
                // "which of them you are in".
                Row {
                  visible: !slot.isSeparator && slot.running
                  anchors.top: slotFill.bottom
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.topMargin: Style.space(2)
                  spacing: Style.space(2)

                  Repeater {
                    model: Math.min(slot.windowCount, 3)

                    delegate: Rectangle {
                      required property int index
                      readonly property bool lead: index === 0
                      width: (lead && slot.focused) ? Style.space(8) : Style.space(3)
                      height: Style.space(3)
                      radius: height / 2
                      color: slot.focused ? Color.accent : Util.alpha(Color.popups.text, 0.45)

                      Behavior on width {
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                      }
                    }
                  }
                }

                MouseArea {
                  id: slotMouse
                  anchors.fill: parent
                  enabled: !slot.isSeparator
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                  cursorShape: slot.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                  // The press point is kept in the row's coordinates, not the
                  // slot's: the dragged slot carries a transform, so its own
                  // local x slides out from under the pointer and a delta taken
                  // there would eat itself.
                  property real pressRowX: 0
                  property bool dragCandidate: false
                  property bool dragHappened: false

                  onPressed: function (mouse) {
                    slotMouse.dragHappened = false
                    slotMouse.dragCandidate = mouse.button === Qt.LeftButton
                      && slot.pinnedIndex >= 0 && root.pinnedCount > 1
                    slotMouse.pressRowX = dockRow.mapFromItem(slotMouse, mouse.x, 0).x
                  }

                  onPositionChanged: function (mouse) {
                    if (!slotMouse.dragCandidate) return
                    var dx = dockRow.mapFromItem(slotMouse, mouse.x, 0).x - slotMouse.pressRowX
                    if (!slot.dragging) {
                      // Below the threshold this is still a click that wobbled.
                      if (Math.abs(dx) < Style.space(8)) return
                      slotMouse.dragHappened = true
                      root.hideTooltip(slot)
                      root.beginDrag(slot.item, slot.pinnedIndex)
                    }
                    var step = root.slotSize + dockRow.spacing
                    var home = slot.x + slot.width / 2
                    var first = home - slot.pinnedIndex * step
                    var last = first + (root.pinnedCount - 1) * step
                    // The icon stays inside the band it can be dropped in:
                    // nowhere it can go is somewhere it cannot land.
                    var center = Math.max(first, Math.min(last, home + dx))
                    root.dragOffsetX = center - home
                    root.dragTo = Math.round((center - first) / step)
                  }

                  onReleased: {
                    slotMouse.dragCandidate = false
                    if (slot.dragging) root.finishDrag(true)
                  }

                  // The grab going away — a monitor change, a compositor
                  // hiccup — drops the icon back where it started.
                  onCanceled: {
                    slotMouse.dragCandidate = false
                    if (slot.dragging) root.finishDrag(false)
                  }

                  onClicked: function (mouse) {
                    // The release that ends a drag is not a click.
                    if (slotMouse.dragHappened) {
                      slotMouse.dragHappened = false
                      return
                    }
                    if (mouse.button === Qt.RightButton) {
                      root.toggleMenu(slot, slot.item)
                    } else if (mouse.button === Qt.MiddleButton) {
                      root.launch(slot.item)
                    } else {
                      root.activateOrLaunch(slot.item)
                    }
                  }

                  onEntered: if (slot.item) root.showTooltip(slot, slot.item.name)
                  onExited: root.hideTooltip(slot)
                  // Unplugging a monitor destroys the slot without a leave
                  // event, which would strand the tooltip on screen.
                  Component.onDestruction: {
                    root.hideTooltip(slot)
                    if (root.menuTarget === slot) root.closeMenu()
                    if (slot.dragging) root.finishDrag(false)
                  }
                }
              }
            }
          }

        }

        // ------------------------------------------------ menu dismissal

        // While a menu is up the dock behaves like the outside of it: a plain
        // click anywhere on the strip dismisses rather than launching, which
        // is what the focus grab already does for everywhere else on screen.
        // Right clicks fall through, so a slot can still close its own menu or
        // hand it straight to its neighbour.
        MouseArea {
          anchors.fill: parent
          z: 10
          enabled: root.menuOpen
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton
          onPressed: root.closeMenu()
        }

        // ----------------------------------------------------- tooltip

        PopupWindow {
          id: tooltipWindow

          visible: root.hoverText !== "" && !root.menuOpen
            && root.targetBelongsToWindow(root.hoverTarget, dockWindow)
          color: "transparent"
          implicitWidth: Math.ceil(tooltipBubble.implicitWidth)
          implicitHeight: Math.ceil(tooltipBubble.implicitHeight)

          anchor {
            id: tooltipAnchor
            window: dockWindow
            adjustment: PopupAdjustment.Slide
            edges: Edges.Top | Edges.Left
            gravity: Edges.Bottom | Edges.Right
            rect.width: 1
            rect.height: 1

            onAnchoring: {
              var target = root.hoverTarget
              if (!root.targetBelongsToWindow(target, dockWindow)) return
              var localX = target.width / 2 - tooltipWindow.implicitWidth / 2
              var localY = -tooltipWindow.implicitHeight - Style.space(8)
              var point = dockWindow.contentItem.mapFromItem(target, localX, localY)
              tooltipAnchor.rect.x = Math.round(point.x)
              tooltipAnchor.rect.y = Math.round(point.y)
            }
          }

          BorderSurface {
            id: tooltipBubble
            implicitWidth: tooltipLabel.implicitWidth + Style.space(20)
            implicitHeight: tooltipLabel.implicitHeight + Style.space(14)
            color: Color.tooltip.background
            borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
            radius: Style.cornerRadius

            Text {
              id: tooltipLabel
              anchors.centerIn: parent
              text: root.hoverText
              textFormat: Text.PlainText
              color: Color.tooltip.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
          }
        }

        // ------------------------------------------------ context menu

        HyprlandFocusGrab {
          active: root.menuOpen && root.targetBelongsToWindow(root.menuTarget, dockWindow)
          windows: [menuWindow, dockWindow]
          onCleared: root.closeMenu()
        }

        PopupWindow {
          id: menuWindow

          readonly property var item: root.menuItem

          visible: root.menuOpen && root.targetBelongsToWindow(root.menuTarget, dockWindow)
          color: "transparent"
          implicitWidth: Math.ceil(menuCard.implicitWidth)
          implicitHeight: Math.ceil(menuCard.implicitHeight)

          anchor {
            id: menuAnchor
            window: dockWindow
            adjustment: PopupAdjustment.Slide
            edges: Edges.Top | Edges.Left
            gravity: Edges.Bottom | Edges.Right
            rect.width: 1
            rect.height: 1

            onAnchoring: {
              var target = root.menuTarget
              if (!root.targetBelongsToWindow(target, dockWindow)) return
              var localX = target.width / 2 - menuWindow.implicitWidth / 2
              var localY = -menuWindow.implicitHeight - Style.space(8)
              var point = dockWindow.contentItem.mapFromItem(target, localX, localY)
              menuAnchor.rect.x = Math.round(point.x)
              menuAnchor.rect.y = Math.round(point.y)
            }
          }

          BorderSurface {
            id: menuCard
            implicitWidth: Math.max(Style.space(180), menuColumn.implicitWidth + Style.space(12))
            implicitHeight: menuColumn.implicitHeight + Style.space(12)
            color: Color.menu.background
            borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)
            radius: Style.cornerRadius

            Column {
              id: menuColumn
              anchors.centerIn: parent
              width: menuCard.implicitWidth - Style.space(12)
              spacing: 0

              Text {
                width: parent.width
                padding: Style.space(6)
                leftPadding: Style.space(10)
                text: root.menuTitle
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Util.alpha(Color.menu.text, 0.55)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Repeater {
                model: root.menuRows

                delegate: Rectangle {
                  id: menuRow

                  // Always reach the row's data through this id. A bare
                  // `modelData` resolves in the delegate's own bindings but not
                  // from a signal handler on a child item, where it is simply
                  // not defined.
                  required property var modelData

                  visible: menuRow.modelData.shown === true
                  width: menuColumn.width
                  height: visible ? Style.spacing.popupRowHeight : 0
                  radius: Math.max(Style.space(4), Style.cornerRadius / 2)
                  color: rowMouse.containsMouse ? Color.menu.selectedBackground : "transparent"

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(10)
                    text: menuRow.modelData.label
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: rowMouse.containsMouse ? Color.menu.selectedText : Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      // Read the row's data through the delegate's id, never a
                      // bare `modelData`: that name resolves in the delegate's
                      // own bindings but not from a handler on a child item.
                      var key = menuRow.modelData.key
                      var item = menuWindow.item
                      root.closeMenu()
                      if (!item) return
                      if (key === "new") root.launch(item)
                      else if (key === "pin") root.togglePin(item)
                      else if (key === "quit") root.quitApp(item)
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // Exposed so a keybinding can pin or launch without the mouse.
  IpcHandler {
    target: "dock"

    function apps(): void {
      root.toggleAppPanel()
    }

    function settings(): void {
      root.toggleSettings()
    }

    function launch(desktopId: string): void {
      var entry = root.resolveEntry(desktopId)
      var id = DockModel.normalizeId(entry ? entry.id : desktopId)
      for (var i = 0; i < root.items.length; i++) {
        if (root.items[i].key === id.toLowerCase()) {
          root.activateOrLaunch(root.items[i])
          return
        }
      }
      root.launch({ id: id, name: id, toplevels: [] })
    }

    function pin(desktopId: string): void {
      var entry = root.resolveEntry(desktopId)
      var id = DockModel.normalizeId(entry ? entry.id : desktopId)
      if (DockModel.isPinned(root.pinned, id)) return
      root.pinned = DockModel.withPin(root.pinned, id)
      root.saveConfig()
      root.rebuild()
    }

    function unpin(desktopId: string): void {
      var entry = root.resolveEntry(desktopId)
      var id = DockModel.normalizeId(entry ? entry.id : desktopId)
      root.pinned = DockModel.withoutPin(root.pinned, id)
      root.saveConfig()
      root.rebuild()
    }
  }
}
