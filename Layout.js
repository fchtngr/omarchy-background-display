// Everything the background and the panel agree on, with no QML, so
// `node --test tests/` runs it directly: the settings document and where a
// preset puts the image on a screen.

var PRESETS = ["fill", "framed", "extend"]

// Framed: the gap around the image, and the frame drawn on it, in logical px.
var FRAME_MARGIN = 24
var FRAME_BORDER = 3

// Cycling intervals the panel accepts, in hours.
var MIN_HOURS = 1
var MAX_HOURS = 168

function isPreset(value) {
  return PRESETS.indexOf(value) !== -1
}

function color(value) {
  var text = String(value || "").trim().toUpperCase()
  return /^#[0-9A-F]{6}$/.test(text) ? text : ""
}

// The settings file, repaired rather than refused: an unknown preset falls back
// to fill, a bad colour to automatic, an interval out of range to the nearest
// one allowed. `cycleHours` 0 is off.
function normalize(raw) {
  var source = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {}
  var displays = {}
  var given = source.displays && typeof source.displays === "object" ? source.displays : {}
  for (var name in given) if (isPreset(given[name])) displays[name] = given[name]
  var hours = Math.round(Number(source.cycleHours) || 0)
  return {
    preset: isPreset(source.preset) ? source.preset : "fill",
    displays: displays,
    frameColor: color(source.frameColor),
    edgeColor: color(source.edgeColor),
    cycleHours: hours <= 0 ? 0 : Math.min(MAX_HOURS, Math.max(MIN_HOURS, hours)),
    shuffle: source.shuffle === true
  }
}

function presetFor(settings, screenName) {
  return settings.displays[screenName] || settings.preset
}

// Sets `preset` on one display, or on every display when `screenName` is
// empty, which also drops the displays' own choices.
function withPreset(settings, screenName, preset) {
  var next = normalize(settings)
  if (!isPreset(preset)) return next
  if (screenName) {
    next.displays[screenName] = preset
  } else {
    next.preset = preset
    next.displays = {}
  }
  return next
}

// Where `preset` draws an imageWidth × imageHeight image on a width × height
// screen whose bar of `barSize` sits on `barEdge`. Framed keeps clear of the
// bar. An image of unknown size fills the space it may use.
function placement(preset, width, height, imageWidth, imageHeight, barEdge, barSize, scale) {
  var k = scale === undefined ? 1 : scale
  var box = { x: 0, y: 0, width: width, height: height }
  if (preset === "fill") return box
  if (preset === "framed") {
    var m = FRAME_MARGIN * k, bar = (barSize || 0) * k
    box = {
      x: m + (barEdge === "left" ? bar : 0),
      y: m + (barEdge === "top" ? bar : 0),
      width: width - 2 * m - (barEdge === "left" || barEdge === "right" ? bar : 0),
      height: height - 2 * m - (barEdge === "top" || barEdge === "bottom" ? bar : 0)
    }
  }
  if (!(imageWidth > 0 && imageHeight > 0)) return box
  var fit = Math.min(box.width / imageWidth, box.height / imageHeight)
  var w = imageWidth * fit, h = imageHeight * fit
  return {
    x: Math.round(box.x + (box.width - w) / 2),
    y: Math.round(box.y + (box.height - h) / 2),
    width: Math.round(w),
    height: Math.round(h)
  }
}

// When the next background is due, in ms since the epoch: an interval after
// the current one was set. 0 when cycling is off.
function nextChange(settings, changedAtMs) {
  if (!settings.cycleHours) return 0
  return changedAtMs + settings.cycleHours * 3600 * 1000
}

// "2 h 5 min", "40 min", "under a minute".
function duration(ms) {
  var minutes = Math.round(Math.max(0, ms) / 60000)
  if (minutes < 1) return "under a minute"
  var h = Math.floor(minutes / 60), m = minutes % 60
  if (!h) return m + " min"
  return m ? h + " h " + m + " min" : h + " h"
}

if (typeof module !== "undefined") {
  module.exports = {
    PRESETS: PRESETS,
    FRAME_MARGIN: FRAME_MARGIN,
    FRAME_BORDER: FRAME_BORDER,
    MIN_HOURS: MIN_HOURS,
    MAX_HOURS: MAX_HOURS,
    normalize: normalize,
    presetFor: presetFor,
    withPreset: withPreset,
    placement: placement,
    nextChange: nextChange,
    duration: duration
  }
}
