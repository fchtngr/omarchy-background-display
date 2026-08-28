import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Ui

Item {
  id: root

  readonly property string currentBackgroundLink: Quickshell.env("HOME")
    + "/.local/state/omarchy/current/background"
  property var manifest: null
  property var shell: null
  property int frameMargin: 24
  property int frameBorderWidth: 3
  property real ambientOpacity: 0.35
  property real ambientBlur: 0.7
  readonly property int topBarHeight: Style.bar.sizeHorizontal
  readonly property color frameBackgroundColor: Color.background
  property string frameColorOverride: ""
  readonly property color frameBorderColor: frameColorOverride || Color.accent
  readonly property bool isFramed: layoutMode === "framed"
  readonly property bool isExtended: layoutMode === "extend"

  property string layoutMode: "default"
  property string autoExtendColor: ""
  property string extendColorOverride: ""
  readonly property color extendColor: extendColorOverride || autoExtendColor || Color.background
  property string extendColorPath: ""
  property string samplingExtendColorPath: ""
  property string pendingExtendColorPath: ""

  onManifestChanged: {
    if (pendingExtendColorPath && !edgeColorProc.running) startExtendColorSample()
    loadLayoutSettings()
  }
  onShellChanged: loadLayoutSettings()

  property string currentBackground: ""
  property string displayedBackground: ""
  property string incomingBackground: ""
  property string oldBackground: ""
  property bool finishingTransition: false
  property int backgroundVersion: 0
  property int revealStartedVersion: -1
  property int pendingThemeVersion: -1
  property string pendingColorsRaw: ""
  property string pendingShellRaw: ""
  property real revealProgress: 1

  function imageUrl(path) {
    return Util.fileUrl(path)
  }

  function normalizedLayoutMode(mode) {
    var value = String(mode || "").trim()
    return value === "framed" || value === "extend" ? value : "default"
  }

  function isLayoutMode(mode) {
    return mode === "default" || mode === "framed" || mode === "extend"
  }

  function storedLayoutSettings() {
    var id = manifest && manifest.id ? String(manifest.id) : ""
    if (!id) return {}
    var entries = shell && shell.shellConfig && Array.isArray(shell.shellConfig.plugins)
      ? shell.shellConfig.plugins : []
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] && String(entries[i].id || "") === id) return entries[i]
    }
    return {}
  }

  function loadLayoutSettings() {
    var settings = storedLayoutSettings()
    extendColorOverride = normalizedColor(settings.extendColor)
    frameColorOverride = normalizedColor(settings.frameColor)
    setLayoutMode(settings.mode, false)
  }

  function normalizedColor(color) {
    var value = String(color || "").trim().toUpperCase()
    return /^#[0-9A-F]{6}$/.test(value) ? value : ""
  }

  function persistLayoutSettings() {
    if (!shell || !manifest || !manifest.id) return
    var settings = { id: String(manifest.id) }
    var stored = storedLayoutSettings()
    for (var key in stored) if (key !== "id") settings[key] = stored[key]
    settings.mode = layoutMode
    settings.extendColor = extendColorOverride
    settings.frameColor = frameColorOverride
    shell.updateEntryInline(manifest.id, settings)
  }

  function setLayoutMode(mode, persist) {
    var next = normalizedLayoutMode(mode)
    layoutMode = next
    if (persist) persistLayoutSettings()
    if (next === "extend" && !extendColorOverride)
      sampleExtendColor(incomingBackground || displayedBackground || currentBackground)
    return next
  }

  function setExtendColor(color, persist) {
    var next = normalizedColor(color)
    if (!next) return "invalid"
    extendColorOverride = next
    if (persist) persistLayoutSettings()
    return next
  }

  function useAutoExtendColor(persist) {
    extendColorOverride = ""
    if (persist) persistLayoutSettings()
    if (layoutMode === "extend")
      sampleExtendColor(incomingBackground || displayedBackground || currentBackground)
    return "auto"
  }

  function setFrameColor(color, persist) {
    var next = normalizedColor(color)
    if (!next) return "invalid"
    frameColorOverride = next
    if (persist) persistLayoutSettings()
    return next
  }

  function useThemeFrameColor(persist) {
    frameColorOverride = ""
    if (persist) persistLayoutSettings()
    return "theme"
  }

  function sampleExtendColor(path) {
    path = String(path || "").trim()
    if (!path || layoutMode !== "extend" || extendColorOverride) return
    extendColorPath = path
    autoExtendColor = ""
    pendingExtendColorPath = path
    if (!edgeColorProc.running) startExtendColorSample()
  }

  function startExtendColorSample() {
    if (!pendingExtendColorPath || !manifest || !manifest.__sourceDir) return
    samplingExtendColorPath = pendingExtendColorPath
    pendingExtendColorPath = ""
    edgeColorProc.command = [manifest.__sourceDir + "/sample-edge-color", samplingExtendColorPath]
    edgeColorProc.running = true
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function setBackground(path, instant) {
    transitionBackground("", path, path, instant, false)
  }

  function transitionBackground(fromPath, path, finalPath, instant, force) {
    path = String(path || "").trim()
    finalPath = String(finalPath || path).trim()
    fromPath = String(fromPath || "").trim()
    if (!path || (!force && finalPath === currentBackground)) return
    currentBackground = finalPath
    sampleExtendColor(path)
    backgroundVersion += 1
    revealStartedVersion = -1

    revealAnimation.stop()
    finishingTransition = false

    if (instant || !displayedBackground) {
      oldBackground = ""
      incomingBackground = ""
      displayedBackground = path
      revealProgress = 1
      return
    }

    oldBackground = fromPath || displayedBackground
    incomingBackground = path
    revealProgress = 0
  }

  function setPendingTheme(colorsB64, shellB64) {
    pendingColorsRaw = Util.decodeBase64(colorsB64)
    pendingShellRaw = Util.decodeBase64(shellB64)
    pendingThemeVersion = backgroundVersion
    pendingThemeFallbackTimer.restart()
  }

  function applyPendingTheme() {
    // Background polling can advance backgroundVersion while a theme switch is
    // pending; the latest theme payload should still apply.
    if (pendingThemeVersion < 0) return
    pendingThemeFallbackTimer.stop()
    Color.loadColors(pendingColorsRaw)
    // Color.loadShell also refreshes Style so the type scale flips with the
    // background reveal instead of waiting for a separate reload path.
    Color.loadShell(pendingShellRaw)
    Style.scheduleRefresh()
    pendingThemeVersion = -1
    pendingColorsRaw = ""
    pendingShellRaw = ""
  }

  function transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64) {
    transitionBackground(fromPath, path, finalPath, false, true)
    setPendingTheme(colorsB64, shellB64)
    if (!incomingBackground || revealProgress >= 1) applyPendingTheme()
  }

  function startReveal(panel) {
    if (!incomingBackground) return
    panel.maskReady = true
    if (revealStartedVersion === backgroundVersion) return
    revealStartedVersion = backgroundVersion
    applyPendingTheme()
    revealAnimation.restart()
  }

  function openSelector() {
    if (!bgSwitchProc.running) bgSwitchProc.running = true
  }

  function openThemeSwitcher() {
    if (!themeSwitchProc.running) themeSwitchProc.running = true
  }

  Process {
    id: bgSwitchProc
    command: ["bash", "-c", "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""]
    onExited: root.refreshBackground()
  }

  Process {
    id: themeSwitchProc
    command: ["bash", "-c", "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\" >/dev/null 2>&1 &"]
    onExited: root.refreshBackground()
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      onStreamFinished: root.setBackground(String(text || "").trim(), false)
    }
  }

  Process {
    id: edgeColorProc
    stdout: StdioCollector {
      onStreamFinished: {
        var value = String(text || "").trim()
        if (root.layoutMode === "extend"
            && root.samplingExtendColorPath === root.extendColorPath
            && /^#[0-9a-fA-F]{6}$/.test(value))
          root.autoExtendColor = value
      }
    }
    onExited: if (root.pendingExtendColorPath) root.startExtendColorSample()
  }

  Connections {
    target: root.shell
    function onShellConfigChanged() {
      root.loadLayoutSettings()
    }
  }

  IpcHandler {
    target: "background"

    function refresh(): void {
      root.refreshBackground()
    }

    function set(path: string): void {
      root.setBackground(path, false)
    }

    function setInstant(path: string): void {
      root.setBackground(path, true)
    }

    function transition(fromPath: string, path: string): void {
      root.transitionBackground(fromPath, path, path, false, false)
    }

    function themeTransition(fromPath: string, path: string, finalPath: string, colorsB64: string, shellB64: string): void {
      root.transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64)
    }

    function layout(mode: string): string {
      mode = String(mode || "").trim()
      if (!root.isLayoutMode(mode)) return "invalid"
      return root.setLayoutMode(mode, true)
    }

    function layoutStatus(): string {
      return root.layoutMode
    }

    function layoutColor(color: string): string {
      return root.setExtendColor(color, true)
    }

    function layoutColorAuto(): string {
      return root.useAutoExtendColor(true)
    }

    function layoutFrameColor(color: string): string {
      return root.setFrameColor(color, true)
    }

    function layoutFrameColorTheme(): string {
      return root.useThemeFrameColor(true)
    }
  }

  Timer {
    id: pendingThemeFallbackTimer
    interval: 300
    repeat: false
    onTriggered: root.applyPendingTheme()
  }

  NumberAnimation {
    id: revealAnimation
    target: root
    property: "revealProgress"
    from: 0
    to: 1
    duration: 420
    easing.type: Easing.InOutCubic
    onFinished: {
      if (root.incomingBackground) {
        root.displayedBackground = root.currentBackground || root.incomingBackground
        root.finishingTransition = true
      }
      root.revealProgress = 1
    }
  }

  Component.onCompleted: {
    refreshBackground()
    loadLayoutSettings()
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: !remapGuard.remapping
      anchors { top: true; bottom: true; left: true; right: true }

      ScreenMoveRemap {
        id: remapGuard
        window: panel
      }
      color: root.isExtended ? root.extendColor : (root.isFramed ? root.frameBackgroundColor : "transparent")
      // Keep render updates enabled. The background layer has been observed to
      // lose its committed buffer while parked with updatesEnabled=false,
      // leaving a black desktop until omarchy-shell is restarted. The wallpaper
      // itself is static, so this favors correctness over a small render-loop
      // optimization.
      updatesEnabled: true

      property bool maskReady: false

      function maybeStartReveal() {
        if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return
        if (incomingFrame.status !== Image.Ready) return
        Qt.callLater(function() {
          if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return
          if (incomingFrame.status !== Image.Ready) return
          root.startReveal(panel)
        })
      }

      WlrLayershell.namespace: "omarchy-background"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      // Use a quiet, blurred copy of the wallpaper behind the framed image.
      Item {
        id: ambientLayer
        anchors.fill: parent
        visible: root.isFramed && root.displayedBackground !== ""
        opacity: root.ambientOpacity
        layer.enabled: visible
        layer.smooth: true
        layer.effect: MultiEffect {
          autoPaddingEnabled: false
          blurEnabled: true
          blur: root.ambientBlur
          blurMax: 128
          blurMultiplier: 1.25
        }

        Image {
          anchors.fill: parent
          source: root.imageUrl(root.displayedBackground)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
          smooth: true
        }
      }

      Image {
        id: base
        anchors.fill: parent
        anchors.topMargin: root.isFramed ? root.frameMargin + root.topBarHeight : 0
        anchors.rightMargin: root.isFramed ? root.frameMargin : 0
        anchors.bottomMargin: root.isFramed ? root.frameMargin : 0
        anchors.leftMargin: root.isFramed ? root.frameMargin : 0
        source: root.imageUrl(root.displayedBackground)
        fillMode: root.layoutMode === "default" ? Image.PreserveAspectCrop : Image.PreserveAspectFit
        asynchronous: true
        cache: true
        onStatusChanged: {
          if (status === Image.Ready && root.finishingTransition) {
            root.incomingBackground = ""
            root.oldBackground = ""
            root.finishingTransition = false
          }
        }
      }

      Rectangle {
        id: baseBorder
        anchors.centerIn: base
        width: base.paintedWidth + root.frameBorderWidth * 2
        height: base.paintedHeight + root.frameBorderWidth * 2
        color: "transparent"
        border.color: root.frameBorderColor
        border.width: root.frameBorderWidth
        visible: root.isFramed && base.status === Image.Ready
      }

      Image {
        id: oldFrame
        anchors.fill: parent
        anchors.topMargin: root.isFramed ? root.frameMargin + root.topBarHeight : 0
        anchors.rightMargin: root.isFramed ? root.frameMargin : 0
        anchors.bottomMargin: root.isFramed ? root.frameMargin : 0
        anchors.leftMargin: root.isFramed ? root.frameMargin : 0
        source: root.imageUrl(root.oldBackground)
        fillMode: root.layoutMode === "default" ? Image.PreserveAspectCrop : Image.PreserveAspectFit
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        visible: root.oldBackground !== "" && root.revealProgress < 1
        onStatusChanged: panel.maybeStartReveal()
      }

      Rectangle {
        id: oldBorder
        anchors.centerIn: oldFrame
        width: oldFrame.paintedWidth + root.frameBorderWidth * 2
        height: oldFrame.paintedHeight + root.frameBorderWidth * 2
        color: "transparent"
        border.color: root.frameBorderColor
        border.width: root.frameBorderWidth
        visible: root.isFramed && oldFrame.visible && oldFrame.status === Image.Ready
      }

      Item {
        id: incomingLayer
        anchors.fill: parent
        visible: root.incomingBackground !== "" && incomingFrame.status === Image.Ready && (root.revealProgress >= 1 || panel.maskReady)
        layer.enabled: root.incomingBackground !== "" && root.revealProgress < 1
        layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: revealMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 0.02
        }

        Image {
          id: incomingFrame
          anchors.fill: parent
          anchors.topMargin: root.isFramed ? root.frameMargin + root.topBarHeight : 0
          anchors.rightMargin: root.isFramed ? root.frameMargin : 0
          anchors.bottomMargin: root.isFramed ? root.frameMargin : 0
          anchors.leftMargin: root.isFramed ? root.frameMargin : 0
          source: root.imageUrl(root.incomingBackground)
          fillMode: root.layoutMode === "default" ? Image.PreserveAspectCrop : Image.PreserveAspectFit
          asynchronous: true
          cache: false
          smooth: true
          mipmap: true
          onStatusChanged: panel.maybeStartReveal()
        }

        Rectangle {
          id: incomingBorder
          anchors.centerIn: incomingFrame
          width: incomingFrame.paintedWidth + root.frameBorderWidth * 2
          height: incomingFrame.paintedHeight + root.frameBorderWidth * 2
          color: "transparent"
          border.color: root.frameBorderColor
          border.width: root.frameBorderWidth
          visible: root.isFramed && incomingFrame.status === Image.Ready
        }
      }

      Item {
        id: revealMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        readonly property real slant: -0.18
        readonly property real centerTop: width / 2 - slant * height / 2
        readonly property real centerBottom: width / 2 + slant * height / 2
        readonly property real reach: width / 2 + Math.abs(slant) * height / 2 + 4
        readonly property real spread: reach * root.revealProgress

        Shape {
          anchors.fill: parent
          antialiasing: true
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            fillColor: "white"
            strokeColor: "transparent"
            startX: revealMask.centerTop - revealMask.spread; startY: 0
            PathLine { x: revealMask.centerTop + revealMask.spread; y: 0 }
            PathLine { x: revealMask.centerBottom + revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerBottom - revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerTop - revealMask.spread; y: 0 }
          }
        }
      }

      Connections {
        target: root
        function onIncomingBackgroundChanged() {
          panel.maskReady = false
          panel.maybeStartReveal()
        }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.openThemeSwitcher()
          else root.openSelector()
          mouse.accepted = true
        }
      }
    }
  }
}
