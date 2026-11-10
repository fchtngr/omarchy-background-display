import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Layout.js" as Layout

// Omarchy's background service with per-display Fill / Fit, independent
// background treatment, frame, spacing, and scheduled cycling.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool suspended: false
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"
  readonly property string currentThemeBackgrounds: stateHome + "/omarchy/current/theme/backgrounds"

  property string currentBackground: ""
  property string displayedBackground: ""
  property string incomingBackground: ""
  property string oldBackground: ""
  // A theme switch names its next background before it has staged the rest of
  // the theme, so the incoming frame can decode while that work runs. A large
  // WebP takes ~130ms to decode at any sourceSize, which the reveal would
  // otherwise wait out after the transition arrives.
  property string preparedBackground: ""
  // The prepare and transition calls travel as separate IPC clients, so a
  // prepare can land after its transition. The path it names then must not be
  // decoded again.
  property string lastTransitionPath: ""
  // Native pixel size per wallpaper path, read from the file header before
  // the image loads. Decoding at screen size only saves memory for wallpapers
  // at least as large as the screen: with PreserveAspectCrop Qt scales the
  // decode up to cover sourceSize, so a smaller wallpaper would cost the
  // screen's worth of pixels instead of its own.
  property var nativeSizes: ({})
  property var sizeQueue: []
  property bool finishingTransition: false
  property int backgroundVersion: 0
  property int reloadVersion: 0
  property int revealStartedVersion: -1
  property int pendingThemeVersion: -1
  property string pendingColorsRaw: ""
  property string pendingShellRaw: ""
  property real revealProgress: 1
  readonly property var settings: store.settings
  readonly property string barEdge: shell && shell.barConfig && shell.barConfig.position
    ? String(shell.barConfig.position) : "top"
  readonly property int barSize: barEdge === "left" || barEdge === "right"
    ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
  readonly property bool needsImageColor: Layout.needsImageColor(settings)

  // The sampled edge colour of each background, shared by all displays.
  property var edgeColors: ({})
  property var edgeQueue: []

  // When the current background was set: the link's own mtime, which every
  // way of setting one (picker, next, theme switch, cycling) renews. Cycling
  // counts from it, so a shell restart does not restart the interval.
  property real changedAt: 0
  readonly property real nextChangeAt: Layout.nextChange(settings, changedAt)

  readonly property bool ready: {
    if (isVideo(displayedBackground)) return true
    if (backgrounds.instances.length === 0) return false
    for (var panel of backgrounds.instances) {
      if (!panel.backgroundReady) return false
    }
    return true
  }

  function isVideo(path) {
    return Util.isVideoPath(path)
  }

  function imageUrl(path) {
    return Util.fileUrl(path)
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
    if (!changedAtProbe.running) changedAtProbe.running = true
  }

  // The desktop must never be left without a wallpaper. A path that stops
  // loading, say one that ran through a theme since replaced, is resolved
  // again from the background link, which a theme switch always repoints.
  // Only a different path is taken, so a file that is there but unreadable
  // cannot loop. Resolving runs out of process, so a background chosen in the
  // meantime wins over what it finds; if that one fails too, it is resolved
  // in turn once the running lookup is done.
  property string failedBackground: ""
  property int recoverVersion: -1

  function recoverBackground(failedPath) {
    if (!failedPath || failedPath !== displayedBackground) return
    failedBackground = failedPath
    if (recoverProc.running) return
    recoverVersion = backgroundVersion
    recoverProc.running = true
  }

  function finishRecovery(path) {
    path = String(path || "").trim()
    var failedPath = failedBackground
    failedBackground = ""
    if (recoverVersion !== backgroundVersion) {
      recoverBackground(failedPath)
      return
    }
    if (!path || path === failedPath) return
    setBackground(path, true)
  }

  function setBackground(path, instant) {
    if (instant) reloadVersion += 1
    transitionBackground("", path, path, instant, instant)
  }

  function transitionBackground(fromPath, path, finalPath, instant, force) {
    path = String(path || "").trim()
    finalPath = String(finalPath || path).trim()
    fromPath = String(fromPath || "").trim()
    if (!path || (!force && finalPath === currentBackground)) return
    if (path !== preparedBackground) preparedBackground = ""
    preparedBackgroundTimer.stop()
    lastTransitionPath = path
    // The incoming frame gates the reveal, so its size is read first.
    requestNativeSize(path)
    requestNativeSize(fromPath || displayedBackground)
    requestNativeSize(finalPath)
    currentBackground = finalPath
    if (!changedAtProbe.running) changedAtProbe.running = true
    backgroundVersion += 1
    failedBackground = ""
    revealStartedVersion = -1

    // OWE draws a video background and fades the last still into it. That
    // still stays on screen until OWE has the first frame and suspends this
    // layer, so the desktop does not show an empty background meanwhile. A
    // running reveal finishes on its incoming still, which OWE fades from.
    if (!instant && !root.suspended && displayedBackground && isVideo(path) && !isVideo(displayedBackground)) return

    revealAnimation.stop()
    finishingTransition = false

    // Video frames are not fed through the image-only reveal stack. Switching
    // instantly also avoids decoding two full videos during a transition.
    if (instant || !displayedBackground || isVideo(path) || isVideo(displayedBackground)) {
      oldBackground = ""
      incomingBackground = ""
      preparedBackground = ""
      displayedBackground = finalPath
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
    Commons.Color.loadColors(pendingColorsRaw)
    // Commons.Color.loadShell also refreshes Style so the type scale flips with the
    // background reveal instead of waiting for a separate reload path.
    Commons.Color.loadShell(pendingShellRaw)
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

  function prepareBackground(path) {
    path = String(path || "").trim()
    // Only a still that is not already on screen is worth decoding ahead.
    if (!path || isVideo(path) || path === lastTransitionPath || path === displayedBackground) return
    requestNativeSize(path)
    preparedBackground = path
    preparedBackgroundTimer.restart()
  }

  function requestNativeSize(path) {
    if (!path || isVideo(path) || nativeSizes[path] !== undefined || sizeQueue.indexOf(path) !== -1) return
    sizeQueue = sizeQueue.concat([path])
    probeNextSize()
  }

  function probeNextSize() {
    if (sizeProbe.running || sizeQueue.length === 0) return
    sizeProbe.path = sizeQueue[0]
    sizeProbe.command = ["magick", "identify", "-ping", "-format", "%w %h", sizeProbe.path]
    sizeProbe.running = true
  }

  // Each theme switch names fresh snapshot paths, so keep only the sizes of
  // the wallpapers still in play.
  function pruneNativeSizes() {
    var kept = {}
    var paths = [displayedBackground, incomingBackground, oldBackground, preparedBackground]
    for (var i = 0; i < paths.length; i++) {
      if (paths[i] && nativeSizes[paths[i]] !== undefined) kept[paths[i]] = nativeSizes[paths[i]]
    }
    nativeSizes = kept
  }

  function sampleEdgeColor(path) {
    if (!needsImageColor || !path || isVideo(path)) return
    if (edgeColors[path] !== undefined || edgeQueue.indexOf(path) !== -1) return
    edgeQueue = edgeQueue.concat([path])
    probeNextEdge()
  }

  function probeNextEdge() {
    if (edgeProbe.running || edgeQueue.length === 0 || !manifest || !manifest.__sourceDir) return
    edgeProbe.path = edgeQueue[0]
    edgeProbe.command = [manifest.__sourceDir + "/sample-edge-color", edgeProbe.path]
    edgeProbe.running = true
  }

  function scheduleCycle() {
    cycleTimer.stop()
    if (!nextChangeAt || changedAt <= 0) return
    // Timers count in int milliseconds; a long interval re-arms in steps.
    cycleTimer.interval = Math.max(1000, Math.min(nextChangeAt - Date.now(), 2147483000))
    cycleTimer.start()
  }

  function cycle() {
    if (!cycleProc.running) cycleProc.running = true
  }

  onDisplayedBackgroundChanged: sampleEdgeColor(displayedBackground)
  onNeedsImageColorChanged: sampleEdgeColor(displayedBackground)
  onNextChangeAtChanged: scheduleCycle()
  onManifestChanged: probeNextEdge()

  SettingsStore {
    id: store
  }

  function openSelector() {
    if (!bgSwitchProc.running) bgSwitchProc.running = true
  }

  function openThemeSwitcher() {
    var payload = JSON.stringify({ source: "themes" })

    // A cloned background may not summon the picker in-process, so it takes
    // the IPC route instead.
    if (!root.shell || !root.shell.summon("omarchy.image-picker", payload))
      Util.execArgv(["omarchy-shell", "shell", "summon", "omarchy.image-picker", payload])
  }

  Process {
    id: bgSwitchProc
    command: ["bash", "-c", "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""]
    onExited: root.refreshBackground()
  }

  Process {
    id: sizeProbe
    property string path: ""
    stdout: StdioCollector { id: sizeProbeOut }
    onExited: function(exitCode) {
      var parts = String(sizeProbeOut.text || "").trim().split(/\s+/)
      var width = exitCode === 0 ? parseInt(parts[0], 10) : 0
      var height = exitCode === 0 ? parseInt(parts[1], 10) : 0
      var known = Object.assign({}, root.nativeSizes)
      // An unreadable header records 0x0, which decodes at screen size.
      known[path] = { width: width > 0 ? width : 0, height: height > 0 ? height : 0 }
      root.nativeSizes = known
      root.sizeQueue = root.sizeQueue.filter(function(queued) { return queued !== sizeProbe.path })
      root.probeNextSize()
    }
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      onStreamFinished: root.setBackground(String(text || "").trim(), false)
    }
  }

  Process {
    id: changedAtProbe
    command: ["stat", "-c", "%Y", root.currentBackgroundLink]
    stdout: StdioCollector {
      onStreamFinished: {
        var seconds = parseInt(String(text || "").trim(), 10)
        if (seconds > 0) root.changedAt = seconds * 1000
      }
    }
  }

  Process {
    id: edgeProbe
    property string path: ""
    stdout: StdioCollector { id: edgeProbeOut }
    onExited: function(exitCode) {
      var value = String(edgeProbeOut.text || "").trim().toUpperCase()
      var known = Object.assign({}, root.edgeColors)
      // A failed sample keeps the theme background, and is not retried.
      known[path] = exitCode === 0 && /^#[0-9A-F]{6}$/.test(value) ? value : ""
      root.edgeColors = known
      root.edgeQueue = root.edgeQueue.filter(function(queued) { return queued !== edgeProbe.path })
      root.probeNextEdge()
    }
  }

  // The next background in Omarchy's order, or a random other one. Both go
  // through omarchy-theme-bg-set, so the link, the picker and the theme's
  // cycling stay the single source of truth.
  Process {
    id: cycleProc
    command: root.settings.shuffle ? [
      "bash", "-c",
      'current=$(readlink -f "$1"); mapfile -d "" -t all < <(find -L "$2" "$3" -maxdepth 1 -type f ' +
      '\\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" -o -iname "*.bmp" ' +
      '-o -iname "*.mp4" -o -iname "*.m4v" -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.mkv" -o -iname "*.avi" \\) -print0 2>/dev/null); ' +
      'others=(); for f in "${all[@]}"; do [[ $(readlink -f "$f") != "$current" ]] && others+=("$f"); done; ' +
      '(( ${#others[@]} )) && omarchy-theme-bg-set "${others[RANDOM % ${#others[@]}]}"',
      "shuffle", root.currentBackgroundLink, root.currentThemeBackgrounds,
      root.home + "/.config/omarchy/backgrounds/" + root.themeName
    ] : ["omarchy-theme-bg-next"]
  }

  Timer {
    id: cycleTimer
    repeat: false
    onTriggered: {
      if (root.nextChangeAt > Date.now() + 1000) root.scheduleCycle()
      else root.cycle()
    }
  }

  FileView {
    id: themeNameFile
    path: root.stateHome + "/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }
  readonly property string themeName: String(themeNameFile.text() || "").trim()

  // The link's target when it exists, or else the theme's first background,
  // so a link left dangling still finds a wallpaper.
  Process {
    id: recoverProc
    command: [
      "bash", "-c",
      'target=$(readlink -f "$1"); if [[ -e $target ]]; then echo "$target"; else ' +
      'find "$2" -maxdepth 1 -type f \\( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \\) | sort | head -n 1; fi',
      "resolve", root.currentBackgroundLink, root.currentThemeBackgrounds
    ]
    stdout: StdioCollector {
      onStreamFinished: root.finishRecovery(text)
    }
  }

  ShellIpc {
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

    function setSuspended(value: string): void {
      root.suspended = value === "true"
    }

    function transition(fromPath: string, path: string): void {
      root.transitionBackground(fromPath, path, path, false, false)
    }

    function themeTransition(fromPath: string, path: string, finalPath: string, colorsB64: string, shellB64: string): void {
      root.transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64)
    }

    function prepare(path: string): void {
      root.prepareBackground(path)
    }
  }

  // A prepared frame that no transition claims, say from a theme switch that
  // failed after naming it, must not hold its decoded texture indefinitely.
  Timer {
    id: preparedBackgroundTimer
    interval: 5000
    repeat: false
    onTriggered: root.preparedBackground = ""
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
    duration: Style.duration(840)
    easing.type: Easing.OutCubic
    onFinished: {
      if (root.incomingBackground) {
        // After a video was chosen during the reveal, the incoming still
        // stays until OWE takes the background.
        root.displayedBackground = root.currentBackground && !root.isVideo(root.currentBackground)
          ? root.currentBackground : root.incomingBackground
        root.finishingTransition = true
      }
      root.revealProgress = 1
    }
  }

  Component.onCompleted: refreshBackground()

  Variants {
    id: backgrounds
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: !remapGuard.remapping && !root.suspended
      anchors { top: true; bottom: true; left: true; right: true }

      ScreenMoveRemap {
        id: remapGuard
        window: panel
      }
      // Videos are OWE's, drawn edge to edge; appearance applies to stills.
      readonly property var appearance: Layout.appearanceFor(root.settings, modelData.name)
      readonly property bool fitted: !root.isVideo(root.displayedBackground) && appearance.mode === "fit"
      readonly property bool framed: fitted && appearance.frame
      readonly property color frameColor: appearance.frameColor || Commons.Color.accent
      color: !fitted ? "transparent" : appearance.background === "image"
        ? (root.edgeColors[root.displayedBackground] || Commons.Color.background)
        : appearance.background === "color" ? (appearance.backgroundColor || Commons.Color.background)
        : Commons.Color.background
      // Keep render updates enabled. The background layer has been observed to
      // lose its committed buffer while parked with updatesEnabled=false,
      // leaving a black desktop until omarchy-shell is restarted. A still
      // wallpaper costs nothing to keep enabled. OWE manages video layers.
      updatesEnabled: true

      property bool maskReady: false
      property int readyFrames: 0
      readonly property bool backgroundReady: base.ready && readyFrames >= 2

      FrameAnimation {
        running: base.ready && panel.readyFrames < 2
        onTriggered: panel.readyFrames += 1
      }

      // Decode the wallpaper at the size this screen can show, not the size
      // it was shipped at. With PreserveAspectCrop Qt takes sourceSize as the
      // area to cover, so this is the smallest decode that still fills the
      // screen. Stock wallpapers go up to 10456x3455 (144 MB as RGBA); a
      // 1080p laptop paid all of that for the 8 MB it can display, and paid
      // it up to three times over during a transition. The images wait for
      // the window's size and the wallpaper's native size so nothing is ever
      // decoded at native size first, and a wallpaper smaller than the screen
      // is decoded at its own size rather than scaled up to cover the screen.
      readonly property bool sized: width > 0 && height > 0

      // Where the appearance puts `path`, in this window's coordinates. A whole
      // image takes the rectangle of its own shape, so the crop below draws
      // it uncut.
      function placement(path) {
        var native = root.nativeSizes[path]
        return Layout.placement(root.isVideo(root.displayedBackground) ? Layout.appearance({}) : appearance, width, height,
          native ? native.width : 0, native ? native.height : 0, root.barEdge, root.barSize)
      }

      // The rectangle the image is drawn into, in physical pixels, is the
      // most worth decoding.
      function decodeSize(path) {
        if (!sized || !path) return Qt.size(0, 0)
        var native = root.nativeSizes[path]
        if (native === undefined) return Qt.size(0, 0)
        var rect = placement(path)
        var decodeWidth = Math.ceil(rect.width * screen.devicePixelRatio)
        var decodeHeight = Math.ceil(rect.height * screen.devicePixelRatio)
        if (native.width > 0 && (native.width < decodeWidth || native.height < decodeHeight)) return Qt.size(native.width, native.height)
        return Qt.size(decodeWidth, decodeHeight)
      }

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

      // Fit can sit over a quiet, blurred copy of the wallpaper. Blur hides
      // detail, so a small decode is enough.
      Item {
        anchors.fill: parent
        visible: panel.fitted && panel.appearance.background === "blur" && root.displayedBackground !== ""
        opacity: 0.35
        layer.enabled: visible
        layer.smooth: true
        layer.effect: MultiEffect {
          autoPaddingEnabled: false
          blurEnabled: true
          blur: 0.7
          blurMax: 64
          blurMultiplier: 1.25
        }

        Image {
          anchors.fill: parent
          source: parent.visible ? root.imageUrl(root.displayedBackground) : ""
          sourceSize.width: Math.ceil(panel.width / 8)
          sourceSize.height: Math.ceil(panel.height / 8)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          smooth: true
        }
      }

      // OWE owns video backgrounds. This layer draws stills, and stays empty
      // behind a video so OWE's own layer shows through.
      BackgroundMedia {
        id: base
        readonly property var rect: panel.placement(root.displayedBackground)
        x: rect.x; y: rect.y; width: rect.width; height: rect.height
        path: root.displayedBackground
        version: root.reloadVersion
        cached: true
        constrainDecode: true
        decodeSize: panel.decodeSize(root.displayedBackground)
        onFailedChanged: if (failed) root.recoverBackground(path)
        onReadyChanged: {
          panel.readyFrames = 0
          if (ready && root.finishingTransition) {
            root.incomingBackground = ""
            root.oldBackground = ""
            root.preparedBackground = ""
            root.finishingTransition = false
            root.pruneNativeSizes()
          }
        }
      }

      // Rounding the fitted rectangle can change its aspect by a fraction
      // of a pixel. PreserveAspectFit keeps even the outermost pixels visible.
      Binding {
        target: base.current
        property: "fillMode"
        value: panel.fitted ? Image.PreserveAspectFit : Image.PreserveAspectCrop
        when: base.current !== null
      }

      Frame {
        target: base
        frameColor: panel.frameColor
        visible: panel.framed && base.ready
      }

      Image {
        id: oldFrame
        readonly property var rect: panel.placement(root.oldBackground)
        x: rect.x; y: rect.y; width: rect.width; height: rect.height
        readonly property size decode: panel.decodeSize(root.oldBackground)
        source: decode.width > 0 ? root.imageUrl(root.oldBackground) : ""
        sourceSize.width: decode.width
        sourceSize.height: decode.height
        fillMode: panel.fitted ? Image.PreserveAspectFit : Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        visible: root.oldBackground !== "" && root.revealProgress < 1
        onStatusChanged: panel.maybeStartReveal()
      }

      Frame {
        target: oldFrame
        frameColor: panel.frameColor
        visible: panel.framed && oldFrame.visible && oldFrame.status === Image.Ready
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
          // The same URL and size as a prepared frame keeps its decoded
          // image, so a transition to it can reveal at once.
          readonly property string framePath: root.incomingBackground || root.preparedBackground
          readonly property var rect: panel.placement(framePath)
          x: rect.x; y: rect.y; width: rect.width; height: rect.height
          readonly property size decode: panel.decodeSize(framePath)
          source: decode.width > 0 ? root.imageUrl(framePath) : ""
          sourceSize.width: decode.width
          sourceSize.height: decode.height
          fillMode: panel.fitted ? Image.PreserveAspectFit : Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          smooth: true
          mipmap: true
          onStatusChanged: panel.maybeStartReveal()
        }

        Frame {
          target: incomingFrame
          frameColor: panel.frameColor
          visible: panel.framed && incomingFrame.status === Image.Ready
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

  // The optional frame, independent of spacing and background treatment.
  component Frame: Rectangle {
    required property Item target
    required property color frameColor
    x: target.x - Layout.FRAME_BORDER
    y: target.y - Layout.FRAME_BORDER
    width: target.width + 2 * Layout.FRAME_BORDER
    height: target.height + 2 * Layout.FRAME_BORDER
    color: "transparent"
    border.color: frameColor
    border.width: Layout.FRAME_BORDER
  }
}
