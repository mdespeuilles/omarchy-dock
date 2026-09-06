import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The dock's settings card, opened by right-clicking the applications button.
//
// Every control applies immediately and the dock writes dock.json itself, the
// same way pinning does — there is no OK button to forget to press. Controls
// are the shell's own ToggleSwitch and ButtonGroup, so they inherit the theme.
Item {
  id: root

  property bool opened: false
  // See AppPanel for why focus is primed Exclusive and then settled to
  // OnDemand: while Exclusive is on, Hyprland routes every pointer event here
  // and the outside-click dismissal fires the moment the card appears.
  property bool focusPrimed: false

  // Current values, bound from the dock.
  property bool showAppsButton: true
  property int iconSize: 40
  // Height of the strip the dock currently occupies, for the size preview.
  property int stripHeight: 0

  signal requestShowAppsButton(bool value)
  signal requestIconSize(int value)

  readonly property var sizeOptions: [
    { value: "32", label: "Small" },
    { value: "40", label: "Medium" },
    { value: "48", label: "Large" },
    { value: "56", label: "Huge" }
  ]

  function open() {
    root.focusPrimed = false
    root.opened = true
  }

  function close() {
    focusPrimeTimer.stop()
    root.focusPrimed = false
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  PanelWindow {
    id: panel

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-dock-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened
      ? (root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
      : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    onVisibleChanged: {
      if (!visible) return
      focusPrimeTimer.restart()
      Qt.callLater(function () { keyCatcher.forceActiveFocus() })
    }

    Timer {
      id: focusPrimeTimer
      interval: 75
      onTriggered: if (root.opened) root.focusPrimed = true
    }

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.focusPrimed
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: root.close()
    }

    BorderSurface {
      id: card

      anchors.centerIn: parent
      width: Style.space(440)
      implicitHeight: content.implicitHeight + card.contentTopInset + card.contentBottomInset
      height: implicitHeight
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, 1)
      padding: Style.spacing.panelPadding

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: {}
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
          }
        }
      }

      Column {
        id: content

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.spacing.panelGap

        Text {
          text: "Dock"
          textFormat: Text.PlainText
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
        }

        // ----------------------------------------------- apps button

        Column {
          width: parent.width
          spacing: Style.spacing.labelGap

          Row {
            width: parent.width
            spacing: Style.spacing.controlGap

            Text {
              width: parent.width - appsToggle.width - Style.spacing.controlGap
              anchors.verticalCenter: parent.verticalCenter
              text: "Applications button"
              textFormat: Text.PlainText
              color: Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            ToggleSwitch {
              id: appsToggle
              anchors.verticalCenter: parent.verticalCenter
              checked: root.showAppsButton
              onToggled: root.requestShowAppsButton(!root.showAppsButton)
            }
          }

          // Turning it off takes away one of the two ways back into this card,
          // so the card names the other one before you do it.
          Text {
            width: parent.width
            text: root.showAppsButton
              ? "The nine-dot button at the left of the dock. Left click opens the applications, right click opens these settings."
              : "Hidden. Right click the dock itself — anywhere but an icon — to open these settings again, or run “omarchy-shell dock settings”. The grid is “omarchy-shell dock apps”."
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Util.alpha(Color.menu.text, 0.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ----------------------------------------------------- height

        Column {
          width: parent.width
          spacing: Style.spacing.labelGap

          Text {
            text: "Height"
            textFormat: Text.PlainText
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          ButtonGroup {
            options: root.sizeOptions
            value: String(root.iconSize)
            onChanged: function (value) { root.requestIconSize(parseInt(value, 10)) }
          }

          Text {
            width: parent.width
            text: "Icons " + root.iconSize + "px — reserves " + root.stripHeight + "px of screen height."
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Util.alpha(Color.menu.text, 0.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }
}
