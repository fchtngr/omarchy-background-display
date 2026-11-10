import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "Layout.js" as Layout

// The bar icon and its panel: which preset each display uses, its colours,
// and cycling through the theme's backgrounds. Everything is written to the
// settings file, which the background service follows.
Panel {
  id: root
  moduleName: "io.github.fchtngr.background-display"
  ipcTarget: "background-display"

  readonly property string home: Quickshell.env("HOME")
  readonly property string backgroundLink: home + "/.local/state/omarchy/current/background"
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")

  readonly property var config: store.settings
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string barEdge: bar && bar.position ? bar.position : "top"
  readonly property int barSize: barEdge === "left" || barEdge === "right"
    ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

  // This bar's display, and the one the panel edits: "" is every display.
  readonly property string barScreen: {
    var window = button.QsWindow.window
    return window && window.screen ? window.screen.name : ""
  }
  readonly property bool multipleDisplays: Quickshell.screens.length > 1
  property string target: ""
  readonly property string editedDisplay: multipleDisplays ? target : ""
  readonly property string shownPreset: Layout.presetFor(config, editedDisplay || barScreen)

  property string currentBackground: ""
  property real changedAt: 0
  property real now: Date.now()
  readonly property real nextChangeAt: Layout.nextChange(config, changedAt)
  readonly property string nextIn: nextChangeAt ? Layout.duration(nextChangeAt - now) : ""
  readonly property bool video: Util.isVideoPath(currentBackground)

  property string sampledFor: ""
  property string sampledEdge: ""
  readonly property color extendColor: config.edgeColor
    || (sampledFor === currentBackground && sampledEdge) || Commons.Color.background
  readonly property color frameColor: config.frameColor || Commons.Color.accent

  // The interval cycling comes back on with.
  property int lastHours: 4
  onConfigChanged: if (config.cycleHours > 0) lastHours = config.cycleHours

  // Which colour the picker is choosing: "frameColor" or "edgeColor".
  property string picking: ""

  function setPreset(preset) {
    store.save(Layout.withPreset(config, editedDisplay, preset))
  }

  function setCycle(on) {
    store.update({ cycleHours: on ? lastHours : 0 })
  }

  function pickColor(key) {
    picking = key
    close()
    if (!picker.running) picker.running = true
  }

  function run(argv) {
    close()
    Quickshell.execDetached(argv)
  }

  function refresh() {
    now = Date.now()
    if (!probe.running) probe.running = true
  }

  function sampleEdge() {
    if (shownPreset !== "extend" || config.edgeColor || video) return
    if (!currentBackground || sampledFor === currentBackground || edgeProbe.running) return
    edgeProbe.path = currentBackground
    edgeProbe.running = true
  }

  onOpenedChanged: if (opened) {
    target = multipleDisplays ? barScreen : ""
    refresh()
  }
  onShownPresetChanged: sampleEdge()
  onCurrentBackgroundChanged: sampleEdge()

  SettingsStore {
    id: store
  }

  // The current background and when it was set, for the previews and the
  // countdown. Read on open and every minute: cheap, and the bar's tooltip
  // stays right without watching the link.
  Process {
    id: probe
    command: ["bash", "-c", 'readlink -f "$1"; stat -c %Y "$1"', "probe", root.backgroundLink]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        root.currentBackground = lines[0] || ""
        var seconds = parseInt(lines[1], 10)
        root.changedAt = seconds > 0 ? seconds * 1000 : 0
      }
    }
  }

  Timer {
    interval: root.opened ? 15000 : 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: edgeProbe
    property string path: ""
    command: [root.pluginDir + "/sample-edge-color", path]
    stdout: StdioCollector { id: edgeOut }
    onExited: function(exitCode) {
      var value = String(edgeOut.text || "").trim().toUpperCase()
      root.sampledFor = path
      root.sampledEdge = exitCode === 0 && /^#[0-9A-F]{6}$/.test(value) ? value : ""
    }
  }

  Process {
    id: picker
    command: ["hyprpicker", "-a"]
    stdout: StdioCollector { id: pickerOut }
    onExited: function(exitCode) {
      var value = String(pickerOut.text || "").trim()
      if (exitCode === 0 && /^#[0-9A-Fa-f]{6}$/.test(value) && root.picking) {
        var patch = {}
        patch[root.picking] = value
        store.update(patch)
      }
      root.picking = ""
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: {
      var preset = Layout.presetFor(root.config, root.barScreen)
      var text = "Background · " + preset.charAt(0).toUpperCase() + preset.slice(1)
      if (root.multipleDisplays && root.barScreen) text += " on " + root.barScreen
      if (root.nextIn) text += " · next in " + root.nextIn
      return text + "\nRight-click: next background"
    }
    iconComponent: Component {
      PresetGlyph {
        preset: Layout.presetFor(root.config, root.barScreen)
        cycling: root.config.cycleHours > 0
        color: button.foreground
      }
    }
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) Quickshell.execDetached(["omarchy-theme-bg-next"])
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(640))

    content: PanelKeyCatcher {
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: column.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: column
          width: scroll.availableWidth
          spacing: Style.space(14)

          // ---------- Title, the file, and the picker ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(titles.implicitHeight, pick.implicitHeight)

            Column {
              id: titles
              anchors.left: parent.left
              anchors.right: pick.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              PanelText {
                text: "Background"
                width: parent.width
                font.pixelSize: Style.font.title
                font.bold: true
              }
              PanelText {
                text: root.currentBackground.replace(/^.*\//, "")
                width: parent.width
                color: root.dim
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
              }
            }

            Button {
              id: pick
              text: "Pick…"
              tooltipText: "Choose another background"
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              bordered: true
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.run(["bash", "-c", 'background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set "$background"'])
            }
          }

          // ---------- The displays, each as it is drawn ----------
          DisplayMap {
            width: parent.width
          }

          Row {
            visible: root.multipleDisplays
            spacing: Style.spacing.xs

            PanelText {
              text: "Give it to"
              color: root.dim
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
              rightPadding: Style.space(4)
            }
            Button {
              text: root.target || root.barScreen
              active: root.target !== ""
              bordered: true
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.target = root.target || root.barScreen
            }
            Button {
              text: "All displays"
              active: root.target === ""
              bordered: true
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.target = ""
            }
          }

          // ---------- Presets ----------
          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            text: "Preset"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            id: presets
            width: parent.width
            spacing: Style.spacing.xs
            readonly property real cardWidth: (width - 2 * spacing) / 3

            Repeater {
              model: [
                { id: "fill", label: "Fill", hint: "crop" },
                { id: "framed", label: "Framed", hint: "blur + frame" },
                { id: "extend", label: "Extend", hint: "edge color" }
              ]

              PresetCard {
                required property var modelData
                width: presets.cardWidth
                preset: modelData.id
                label: modelData.label
                hint: modelData.hint
              }
            }
          }

          Row {
            visible: root.shownPreset !== "fill"
            spacing: Style.spacing.xs
            readonly property string key: root.shownPreset === "framed" ? "frameColor" : "edgeColor"

            Rectangle {
              width: Style.space(14)
              height: width
              color: root.shownPreset === "framed" ? root.frameColor : root.extendColor
              border.color: Util.alpha(root.foreground, 0.4)
              border.width: 1
              anchors.verticalCenter: parent.verticalCenter
            }
            PanelText {
              text: root.shownPreset === "framed" ? "Frame" : "Edge"
              color: root.dim
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
              leftPadding: Style.space(2)
              rightPadding: Style.space(6)
            }
            Button {
              text: root.shownPreset === "framed" ? "Theme accent" : "From the image"
              active: !root.config[parent.key]
              bordered: true
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: {
                var patch = {}
                patch[parent.key] = ""
                store.update(patch)
              }
            }
            Button {
              text: "Pick from screen"
              iconText: "󰈊"
              active: !!root.config[parent.key]
              bordered: true
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.pickColor(parent.key)
            }
          }

          // ---------- Cycling ----------
          PanelSeparator { foreground: root.foreground }

          Item {
            width: parent.width
            implicitHeight: Math.max(cycleLabels.implicitHeight, cycleSwitch.implicitHeight)

            Column {
              id: cycleLabels
              anchors.left: parent.left
              anchors.right: cycleSwitch.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              PanelText {
                text: "Cycle backgrounds"
                width: parent.width
                font.pixelSize: Style.font.body
              }
              PanelText {
                text: root.config.cycleHours > 0
                  ? (root.config.shuffle ? "Shuffled" : "In order") + " · theme and your backgrounds"
                  : "Off · the background changes when you pick one"
                width: parent.width
                color: root.dim
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            ToggleSwitch {
              id: cycleSwitch
              checked: root.config.cycleHours > 0
              foreground: root.foreground
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              onToggled: root.setCycle(!checked)
            }
          }

          Item {
            visible: root.config.cycleHours > 0
            width: parent.width
            implicitHeight: Math.max(hours.implicitHeight, shuffle.implicitHeight)

            NumberField {
              id: hours
              label: "Every (hours)"
              from: Layout.MIN_HOURS
              to: Layout.MAX_HOURS
              value: root.config.cycleHours
              foreground: root.foreground
              fontFamily: root.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              onModified: function(v) { store.update({ cycleHours: v }) }
            }

            Button {
              id: shuffle
              text: "Shuffle"
              active: root.config.shuffle
              bordered: true
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              onClicked: store.update({ shuffle: !root.config.shuffle })
            }
          }

          Item {
            visible: root.config.cycleHours > 0
            width: parent.width
            implicitHeight: next.implicitHeight

            PanelText {
              text: root.nextIn ? "Next change in " + root.nextIn : ""
              color: root.dim
              font.pixelSize: Style.font.caption
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Button {
              id: next
              text: "Next now"
              iconText: "󰒭"
              bordered: true
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              anchors.right: parent.right
              onClicked: Quickshell.execDetached(["omarchy-theme-bg-next"])
            }
          }

          Item {
            width: parent.width
            height: Style.space(2)
          }
        }
      }
    }
  }

  component PanelText: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
  }

  // The displays laid out as they are arranged, each drawn with its preset.
  // Clicking one makes it the display the presets apply to.
  component DisplayMap: Item {
    id: map

    readonly property var screens: Quickshell.screens
    readonly property var bounds: {
      var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
      for (var i = 0; i < screens.length; i++) {
        var s = screens[i]
        x0 = Math.min(x0, s.x); y0 = Math.min(y0, s.y)
        x1 = Math.max(x1, s.x + s.width); y1 = Math.max(y1, s.y + s.height)
      }
      return screens.length ? { x: x0, y: y0, width: x1 - x0, height: y1 - y0 } : { x: 0, y: 0, width: 16, height: 9 }
    }
    readonly property real gap: Style.space(4)
    readonly property real factor: Math.min(width / bounds.width, Style.space(150) / bounds.height)
    implicitHeight: Math.round(bounds.height * factor)

    Repeater {
      model: map.screens

      Item {
        id: tile
        required property var modelData
        readonly property string name: modelData.name
        readonly property bool edited: root.editedDisplay === name || (root.multipleDisplays && root.editedDisplay === "")
        x: Math.round((modelData.x - map.bounds.x) * map.factor + (map.width - map.bounds.width * map.factor) / 2) + map.gap / 2
        y: Math.round((modelData.y - map.bounds.y) * map.factor) + map.gap / 2
        width: Math.round(modelData.width * map.factor) - map.gap
        height: Math.round(modelData.height * map.factor) - map.gap

        Thumb {
          anchors.fill: parent
          path: root.video ? "" : root.currentBackground
          preset: Layout.presetFor(root.config, tile.name)
          ratio: width / tile.modelData.width
          barEdge: root.barEdge
          barSize: root.barSize
          frameColor: root.frameColor
          extendColor: root.extendColor
        }

        Rectangle {
          anchors.fill: parent
          color: "transparent"
          border.width: tile.edited ? 2 : 1
          border.color: tile.edited ? Commons.Color.accent : Util.alpha(root.foreground, 0.3)
        }

        Text {
          visible: root.multipleDisplays
          text: tile.name
          textFormat: Text.PlainText
          color: root.foreground
          style: Text.Outline
          styleColor: Commons.Color.background
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.margins: Style.space(5)
        }

        MouseArea {
          anchors.fill: parent
          enabled: root.multipleDisplays
          cursorShape: Qt.PointingHandCursor
          onClicked: root.target = tile.name
        }
      }
    }
  }

  component PresetCard: Rectangle {
    id: card
    property string preset
    property string label
    property string hint
    readonly property bool active: root.shownPreset === preset

    implicitHeight: cardColumn.implicitHeight + 2 * Style.space(6)
    color: active ? Style.selectedFillFor(root.foreground, Commons.Color.accent)
      : cardMouse.containsMouse ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent"
    border.width: 1
    border.color: active ? Commons.Color.accent : Util.alpha(root.foreground, 0.2)

    Column {
      id: cardColumn
      anchors.fill: parent
      anchors.margins: Style.space(6)
      spacing: Style.space(6)

      Thumb {
        readonly property var display: {
          var name = root.editedDisplay || root.barScreen
          for (var i = 0; i < Quickshell.screens.length; i++)
            if (Quickshell.screens[i].name === name) return Quickshell.screens[i]
          return Quickshell.screens.length ? Quickshell.screens[0] : null
        }
        width: parent.width
        height: display ? Math.round(width * display.height / display.width) : Math.round(width * 9 / 16)
        path: root.video ? "" : root.currentBackground
        preset: card.preset
        ratio: display ? width / display.width : 1
        barEdge: root.barEdge
        barSize: root.barSize
        frameColor: root.frameColor
        extendColor: root.extendColor
      }

      Item {
        width: parent.width
        implicitHeight: cardLabel.implicitHeight

        Text {
          id: cardLabel
          text: card.label
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: card.active
        }
        Text {
          text: card.hint
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          anchors.right: parent.right
          anchors.baseline: cardLabel.baseline
          visible: cardLabel.implicitWidth + implicitWidth + Style.space(6) < parent.width
        }
      }
    }

    MouseArea {
      id: cardMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.setPreset(card.preset)
    }
  }

  // The bar icon: a screen with the image placed as the preset places it, and
  // a dot while the backgrounds cycle.
  component PresetGlyph: Item {
    id: glyph
    property string preset: "fill"
    property bool cycling: false
    property color color

    readonly property real unit: Math.min(width, height) / 16

    Rectangle {
      id: screenOutline
      x: glyph.unit; y: glyph.unit * 2.5
      width: glyph.unit * 14; height: glyph.unit * 10
      color: "transparent"
      border.color: glyph.color
      border.width: Math.max(1, Math.round(glyph.unit * 1.3))
    }
    Rectangle {
      readonly property real inset: glyph.preset === "fill" ? 2.5 : glyph.preset === "framed" ? 3.5 : 0
      x: screenOutline.x + glyph.unit * (glyph.preset === "extend" ? 4 : inset)
      y: screenOutline.y + glyph.unit * (glyph.preset === "extend" ? 1.5 : glyph.preset === "framed" ? 2.5 : 2.5)
      width: screenOutline.width - glyph.unit * 2 * (glyph.preset === "extend" ? 4 : inset)
      height: screenOutline.height - glyph.unit * 2 * (glyph.preset === "extend" ? 1.5 : 2.5)
      color: glyph.color
    }
    Repeater {
      model: glyph.preset === "extend" ? [1.5, 10.5] : []
      Rectangle {
        required property real modelData
        x: screenOutline.x + glyph.unit * modelData
        y: screenOutline.y + glyph.unit * 1.5
        width: glyph.unit * 2; height: screenOutline.height - glyph.unit * 3
        color: glyph.color
        opacity: 0.4
      }
    }
    Rectangle {
      visible: glyph.cycling
      width: glyph.unit * 4.4; height: width; radius: width / 2
      x: glyph.unit * 13.5 - width / 2; y: glyph.unit * 13 - height / 2
      color: Commons.Color.background
      Rectangle {
        anchors.centerIn: parent
        width: parent.width * 0.64; height: width; radius: width / 2
        color: Commons.Color.accent
      }
    }
  }
}
