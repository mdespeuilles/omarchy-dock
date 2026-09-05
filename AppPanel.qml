import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The full-screen application grid the dock's leading button opens.
//
// Search is not ours: `appLibrary.sortedEntries(query)` already filters hidden
// and NoDisplay entries, scores them, and sorts. Typing here just feeds it a
// query. The keyboard handling follows the emoji overlay — a plain key catcher
// building the filter string rather than a focused TextField, which is what
// makes the panel usable the instant it maps.
Item {
  id: root

  property var appLibrary: null
  // Desktop ids currently on the dock, so a tile can show it is pinned and the
  // context menu can say Pin or Unpin.
  property var pinnedIds: []
  property bool opened: false
  // Layer-shell focus is primed Exclusive then settled to OnDemand, the same
  // dance Ui/KeyboardPanel does. Exclusive is the only mode that reliably takes
  // keyboard focus at map time, but while it is on Hyprland routes every
  // pointer event on any output to this surface — which fired the dismissal
  // MouseArea the instant the panel appeared and closed it again.
  property bool focusPrimed: false

  signal launchRequested(string desktopId, string name)
  signal pinToggleRequested(string desktopId)

  property string filterText: ""
  property int selectedIndex: 0
  // Right-click menu state. -1 is closed; the point is in card coordinates.
  property int menuIndex: -1
  property real menuX: 0
  property real menuY: 0

  // sortedEntries returns scoring rows — { entry, score, key, name } — not the
  // entries themselves, and its `name` is lowercased for sorting. Unwrap to the
  // real DesktopEntry here so tiles get the proper name and a resolvable icon.
  readonly property var results: {
    if (!root.appLibrary) return []
    // Touching the generation here makes this re-evaluate when apps are
    // installed or removed while the panel is open.
    var generation = root.appsGeneration
    var rows = root.appLibrary.sortedEntries(root.filterText) || []
    var out = []
    for (var i = 0; i < rows.length; i++) {
      var entry = rows[i] ? rows[i].entry : null
      if (entry) out.push(entry)
    }
    return out
  }
  property int appsGeneration: 0

  readonly property var selectedEntry: (root.selectedIndex >= 0 && root.selectedIndex < root.results.length)
    ? root.results[root.selectedIndex] : null
  readonly property var menuEntry: (root.menuIndex >= 0 && root.menuIndex < root.results.length)
    ? root.results[root.menuIndex] : null

  function normalizeId(value) {
    var s = String(value || "").trim()
    if (s.length > 8 && s.slice(-8) === ".desktop") s = s.slice(0, -8)
    return s
  }

  function isPinned(desktopId) {
    var key = root.normalizeId(desktopId).toLowerCase()
    for (var i = 0; i < root.pinnedIds.length; i++)
      if (root.normalizeId(root.pinnedIds[i]).toLowerCase() === key) return true
    return false
  }

  function open() {
    root.filterText = ""
    root.selectedIndex = 0
    root.menuIndex = -1
    root.focusPrimed = false
    root.opened = true
    // The icon index never re-scans on its own, so an app installed since the
    // shell started would otherwise show the generic fallback icon.
    if (root.appLibrary) root.appLibrary.refreshIcons()
  }

  function close() {
    focusPrimeTimer.stop()
    root.focusPrimed = false
    root.opened = false
    root.menuIndex = -1
    root.filterText = ""
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function setFilter(value) {
    root.filterText = String(value || "")
    root.selectedIndex = 0
    root.menuIndex = -1
    grid.positionViewAtBeginning()
  }

  function moveSelection(delta) {
    if (root.results.length === 0) return
    var next = root.selectedIndex + delta
    if (next < 0) next = 0
    if (next > root.results.length - 1) next = root.results.length - 1
    root.selectedIndex = next
    grid.positionViewAtIndex(next, GridView.Contain)
  }

  function launchIndex(index) {
    if (index < 0 || index >= root.results.length) return
    var entry = root.results[index]
    if (!entry) return
    root.launchRequested(root.normalizeId(entry.id), String(entry.name || entry.id))
    root.close()
  }

  function openMenu(index, x, y) {
    root.menuIndex = index
    root.menuX = x
    root.menuY = y
  }

  Connections {
    target: root.appLibrary
    ignoreUnknownSignals: true
    function onAppsChanged() { root.appsGeneration++ }
  }

  PanelWindow {
    id: panel

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-dock-apps"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened
      ? (root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
      : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Layer-shell grants the surface focus during the prime, but Qt still needs
    // an active-focus target inside it before Keys.onPressed fires.
    onVisibleChanged: {
      if (!visible) return
      focusPrimeTimer.restart()
      Qt.callLater(function () { keyCatcher.forceActiveFocus() })
    }

    readonly property int cardWidth: Math.round(Math.min(panel.width * 0.74, Style.space(1080)))
    readonly property int cardHeight: Math.round(Math.min(panel.height * 0.76, Style.space(760)))
    readonly property int cellWidth: Style.space(124)
    readonly property int cellHeight: Style.space(120)
    readonly property int tileIcon: Style.space(52)

    Timer {
      id: focusPrimeTimer
      // Enough for a few Qt/Wayland commit cycles, short enough that the
      // compositor-wide Exclusive phase is imperceptible.
      interval: 75
      onTriggered: if (root.opened) root.focusPrimed = true
    }

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    // Click anywhere outside the card to dismiss. Armed only once focus has
    // settled: no click within 75ms of the panel appearing is a real one.
    MouseArea {
      anchors.fill: parent
      enabled: root.focusPrimed
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: root.close()
    }

    BorderSurface {
      id: card

      anchors.centerIn: parent
      width: panel.cardWidth
      height: panel.cardHeight
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)
      padding: Style.spacing.panelPadding

      // Swallow clicks that land on the card itself so they do not reach the
      // dismissal area behind it — but do close an open context menu.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.menuIndex = -1
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          if (event.key === Qt.Key_Escape) {
            if (root.menuIndex >= 0) root.menuIndex = -1
            else if (root.filterText) root.setFilter("")
            else root.close()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            root.moveSelection(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            root.moveSelection(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.moveSelection(-grid.columns)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.moveSelection(grid.columns)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.launchIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.text && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.panelGap

        // ------------------------------------------------------ search

        Row {
          id: searchRow
          width: parent.width
          height: Style.space(34)
          spacing: Style.spacing.controlGap

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "⌕"
            color: Color.menu.text
            opacity: 0.5
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: searchRow.width - Style.space(34)
            text: root.filterText || "Type to search applications…"
            textFormat: Text.PlainText
            color: Color.menu.text
            opacity: root.filterText ? 1 : 0.5
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }
        }

        Rectangle {
          width: parent.width
          height: Math.max(1, Style.space(1))
          color: Util.alpha(Color.menu.text, 0.15)
        }

        // -------------------------------------------------------- grid

        Item {
          width: parent.width
          height: parent.height - searchRow.height - Style.space(1) - Style.spacing.panelGap * 2

          GridView {
            id: grid

            readonly property int columns: Math.max(1, Math.floor(width / panel.cellWidth))

            anchors.fill: parent
            visible: root.results.length > 0
            model: root.results
            cellWidth: Math.floor(width / grid.columns)
            cellHeight: panel.cellHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
              id: tile

              required property var modelData
              required property int index

              readonly property string entryId: root.normalizeId(tile.modelData ? tile.modelData.id : "")
              readonly property bool selected: root.selectedIndex === tile.index
              readonly property bool menuHere: root.menuIndex === tile.index

              width: grid.cellWidth
              height: grid.cellHeight

              Rectangle {
                anchors.fill: parent
                anchors.margins: Style.space(4)
                radius: Math.max(Style.space(8), Style.cornerRadius)
                color: tile.menuHere ? Style.selectedFill
                  : (tileMouse.containsMouse || tile.selected ? Style.hoverFill : "transparent")
                border.width: tile.selected ? Math.max(1, Style.selectedBorderWidth) : 0
                border.color: tile.selected ? Style.selectedBorderColor : "transparent"

                Behavior on color {
                  ColorAnimation { duration: 110; easing.type: Easing.OutCubic }
                }
              }

              Column {
                anchors.centerIn: parent
                width: parent.width - Style.space(14)
                spacing: Style.space(7)

                Item {
                  width: panel.tileIcon
                  height: panel.tileIcon
                  anchors.horizontalCenter: parent.horizontalCenter

                  Image {
                    anchors.fill: parent
                    source: root.appLibrary && tile.modelData
                      ? root.appLibrary.iconSource(tile.modelData.icon) : ""
                    sourceSize.width: panel.tileIcon * 2
                    sourceSize.height: panel.tileIcon * 2
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    mipmap: true
                  }

                  // Already on the dock. Small, but it is what stops you
                  // pinning the same app twice.
                  Rectangle {
                    visible: root.isPinned(tile.entryId)
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    width: Style.space(10)
                    height: width
                    radius: width / 2
                    color: Color.accent
                    border.width: Math.max(1, Style.space(1))
                    border.color: Color.menu.background
                  }
                }

                Text {
                  width: parent.width
                  text: tile.modelData ? String(tile.modelData.name || tile.modelData.id) : ""
                  textFormat: Text.PlainText
                  horizontalAlignment: Text.AlignHCenter
                  color: Color.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  maximumLineCount: 2
                  wrapMode: Text.Wrap
                }
              }

              MouseArea {
                id: tileMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor

                onEntered: if (root.menuIndex < 0) root.selectedIndex = tile.index

                onClicked: function (mouse) {
                  // Read the index off the delegate id before anything can
                  // rebuild the model underneath this handler.
                  var idx = tile.index
                  if (mouse.button === Qt.RightButton) {
                    var point = card.mapFromItem(tile, mouse.x, mouse.y)
                    root.openMenu(idx, point.x, point.y)
                  } else {
                    root.launchIndex(idx)
                  }
                }
              }
            }
          }

          Text {
            visible: root.results.length === 0
            anchors.centerIn: parent
            text: root.filterText
              ? "No application matches “" + root.filterText + "”"
              : "No applications found"
            textFormat: Text.PlainText
            color: Util.alpha(Color.menu.text, 0.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }
      }

      // ---------------------------------------------------- right-click

      BorderSurface {
        id: tileMenu

        visible: root.menuIndex >= 0 && root.menuEntry !== null
        // Keep the card from clipping the menu when the click is near an edge.
        x: Math.max(0, Math.min(root.menuX, card.width - tileMenu.width))
        y: Math.max(0, Math.min(root.menuY, card.height - tileMenu.height))
        implicitWidth: Style.space(200)
        implicitHeight: menuColumn.implicitHeight + Style.space(10)
        width: implicitWidth
        height: implicitHeight
        radius: Math.max(Style.space(6), Style.cornerRadius)
        color: Color.menu.background
        borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)

        Column {
          id: menuColumn
          anchors.centerIn: parent
          width: tileMenu.width - Style.space(10)
          spacing: 0

          Repeater {
            model: [
              { key: "launch", label: "Launch" },
              { key: "pin", label: root.menuEntry && root.isPinned(root.menuEntry.id)
                  ? "Unpin from dock" : "Pin to dock" }
            ]

            delegate: Rectangle {
              id: menuRow

              // Through the id, never bare: `modelData` does not resolve from a
              // handler on a child item.
              required property var modelData

              width: menuColumn.width
              height: Style.spacing.popupRowHeight
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
                  var key = menuRow.modelData.key
                  var index = root.menuIndex
                  var entry = root.menuEntry
                  root.menuIndex = -1
                  if (!entry) return
                  if (key === "launch") root.launchIndex(index)
                  else root.pinToggleRequested(root.normalizeId(entry.id))
                }
              }
            }
          }
        }
      }
    }
  }
}
