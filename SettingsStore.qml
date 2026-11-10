import QtQuick
import Quickshell
import Quickshell.Io
import "Layout.js" as Layout

// The plugin's settings, at ~/.config/omarchy/background-display.json. The
// background and every bar panel each keep one of these: the panel writes it,
// and every copy follows the file, so a change reaches the desktop and the
// other monitors' panels the same way a hand-edit does.
Item {
  id: root

  readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
  readonly property string path: configDir + "/omarchy/background-display.json"

  property var settings: Layout.normalize({})
  property bool ready: false

  function save(next) {
    settings = Layout.normalize(next)
    file.setText(JSON.stringify(settings, null, 2) + "\n")
  }

  function update(patch) {
    var next = JSON.parse(JSON.stringify(settings))
    for (var key in patch) next[key] = patch[key]
    save(next)
  }

  FileView {
    id: file
    path: root.path
    watchChanges: true
    atomicWrites: true
    printErrors: false

    onLoaded: {
      try {
        root.settings = Layout.normalize(JSON.parse(text()))
      } catch (error) {
        // A broken hand-edit keeps what is on screen rather than resetting it.
        console.warn("background-display: settings are not valid JSON, keeping the last good ones:", error)
      }
      root.ready = true
    }
    // First run: the defaults, written only once something is changed.
    onLoadFailed: root.ready = true
    // text() is stale inside the change signal; reload and parse in onLoaded.
    onFileChanged: reload()
  }

  // A FileView on a path that does not exist yet can stay silent.
  Timer {
    interval: 500
    running: !root.ready
    onTriggered: root.ready = true
  }

  Component.onCompleted: file.reload()
}
