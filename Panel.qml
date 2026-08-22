import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "thomas.background"

  readonly property var backgroundService: bar && bar.shell
    ? bar.shell.serviceFor(moduleName)
    : null
  readonly property string mode: backgroundService ? backgroundService.layoutMode : "default"
  readonly property var modes: [
    { value: "default", label: "Default" },
    { value: "framed", label: "Framed" },
    { value: "extend", label: "Extend" }
  ]
  property int cursorIndex: -1

  function modeIndex() {
    for (var i = 0; i < modes.length; i++)
      if (modes[i].value === mode) return i
    return 0
  }

  function selectMode(value) {
    if (backgroundService) backgroundService.setLayoutMode(value, true)
  }

  function activateCursor() {
    if (cursorIndex >= 0 && cursorIndex < modes.length)
      selectMode(modes[cursorIndex].value)
  }

  onOpenedChanged: cursorIndex = opened ? modeIndex() : -1

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    tooltipText: "Background layout"
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        var delta = dx !== 0 ? dx : dy
        if (delta !== 0)
          root.cursorIndex = Math.max(0, Math.min(root.modes.length - 1, root.cursorIndex + delta))
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(14)

        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            text: ""
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Background"
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: root.mode.toUpperCase()
              color: Qt.darker(root.barForeground, 1.4)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
          }
        }

        PanelSeparator {
          foreground: root.barForeground
        }

        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "LAYOUT"
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }

          ButtonGroup {
            anchors.horizontalCenter: parent.horizontalCenter
            options: root.modes
            value: root.mode
            foreground: root.barForeground
            background: Color.popups.background
            accent: Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            focusable: false
            cursorIndex: root.cursorIndex
            onChanged: function(value) { root.selectMode(value) }
            onHovered: function(index, hovered) {
              if (hovered) root.cursorIndex = index
            }
          }
        }
      }
    }
  }
}
