import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons
import "Layout.js" as Layout

// The current background with the display's appearance, shrunk to this
// item: the display map and the fit cards. It places the image with the
// same Layout.placement the desktop uses, scaled by `ratio`.
Item {
  id: root

  property string path: ""
  property var appearance: Layout.appearance({})
  // Thumbnail px per logical screen px.
  property real ratio: 1
  property string barEdge: "top"
  property int barSize: 0
  property color imageColor: Commons.Color.background
  readonly property bool fitted: appearance.mode === "fit"

  // Every thumbnail asks for the same small decode, so they share one image.
  readonly property url source: path ? Util.fileUrl(path) : ""
  readonly property int decodeWidth: 480
  readonly property var rect: Layout.placement(appearance, width, height,
    image.implicitWidth, image.implicitHeight, barEdge, barSize, ratio)

  clip: true

  Rectangle {
    anchors.fill: parent
    color: !root.fitted ? "transparent" : root.appearance.background === "image"
      ? root.imageColor : root.appearance.background === "color"
      ? (root.appearance.backgroundColor || Commons.Color.background) : Commons.Color.background
  }

  Item {
    anchors.fill: parent
    visible: root.fitted && root.appearance.background === "blur"
    opacity: 0.35
    layer.enabled: visible
    layer.effect: MultiEffect {
      autoPaddingEnabled: false
      blurEnabled: true
      blur: 0.6
      blurMax: 16
    }

    Image {
      anchors.fill: parent
      source: parent.visible ? root.source : ""
      sourceSize.width: root.decodeWidth
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
    }
  }

  Image {
    id: image
    x: root.rect.x; y: root.rect.y; width: root.rect.width; height: root.rect.height
    source: root.source
    sourceSize.width: root.decodeWidth
    fillMode: root.fitted ? Image.PreserveAspectFit : Image.PreserveAspectCrop
    asynchronous: true
    smooth: true
  }

  Rectangle {
    readonly property real line: Math.max(1, Layout.FRAME_BORDER * root.ratio)
    visible: root.fitted && root.appearance.frame && image.status === Image.Ready
    x: image.x - line; y: image.y - line
    width: image.width + 2 * line; height: image.height + 2 * line
    color: "transparent"
    border.color: root.appearance.frameColor || Commons.Color.accent
    border.width: line
  }
}
