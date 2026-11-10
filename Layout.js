// Shared settings and geometry for the desktop and previews. No QML, so
// the model can also be exercised with node --test tests/.
var FRAME_BORDER = 3
var MAX_SPACING = 256
var MIN_HOURS = 1
var MAX_HOURS = 168

function color(value) {
  var text = String(value || "").trim().toUpperCase()
  return /^#[0-9A-F]{6}$/.test(text) ? text : ""
}

function validObject(value) {
  return value && typeof value === "object" && !Array.isArray(value)
}

// Old presets become independent options, preserving their appearance.
function appearance(raw) {
  var source = validObject(raw) ? raw : {}
  var legacy = typeof raw === "string" ? raw : source.preset
  var framed = legacy === "framed"
  var extended = legacy === "extend"
  var spacing = Number(source.spacing)
  return {
    mode: source.mode === "fit" || (!source.mode && (framed || extended)) ? "fit" : "fill",
    background: ["blur", "image", "color"].indexOf(source.background) !== -1
      ? source.background : extended ? (color(source.edgeColor) ? "color" : "image") : "blur",
    frame: source.frame === undefined ? framed : source.frame === true,
    spacing: source.spacing === undefined ? (framed ? 24 : 0)
      : isFinite(spacing) ? Math.max(0, Math.min(MAX_SPACING, Math.round(spacing))) : 0,
    avoidBar: source.avoidBar === undefined ? framed : source.avoidBar === true,
    frameColor: color(source.frameColor),
    backgroundColor: color(source.backgroundColor) || color(source.edgeColor)
  }
}

function normalize(raw) {
  var source = validObject(raw) ? raw : {}
  var next = appearance(source)
  next.displays = {}
  var given = validObject(source.displays) ? source.displays : {}
  for (var name in given) {
    var value = given[name]
    if (validObject(value)) next.displays[name] = appearance(value)
    else if (["fill", "framed", "extend"].indexOf(value) !== -1) {
      // Colours were global in the old file.
      next.displays[name] = appearance({ preset: value,
        frameColor: source.frameColor, edgeColor: source.edgeColor })
    }
  }
  var hours = Math.round(Number(source.cycleHours) || 0)
  next.cycleHours = hours <= 0 ? 0 : Math.min(MAX_HOURS, Math.max(MIN_HOURS, hours))
  next.shuffle = source.shuffle === true
  return next
}

function appearanceFor(settings, screenName) {
  return appearance(settings.displays[screenName] || settings)
}

// Editing all displays replaces their overrides. A single-display edit starts
// from its complete current appearance, keeping all unrelated choices.
function withAppearance(settings, screenName, patch) {
  var next = normalize(settings)
  var edited = appearanceFor(next, screenName)
  for (var key in patch) edited[key] = patch[key]
  edited = appearance(edited)
  if (screenName) next.displays[screenName] = edited
  else {
    for (var key in edited) next[key] = edited[key]
    next.displays = {}
  }
  return next
}

function needsImageColor(settings) {
  function needs(options) { return options.mode === "fit" && options.background === "image" }
  if (needs(settings)) return true
  for (var name in settings.displays) if (needs(settings.displays[name])) return true
  return false
}

// Spacing and bar clearance are independent of both the frame and background.
// Reserve room for the frame inside the available box, even at zero spacing.
function placement(options, width, height, imageWidth, imageHeight, barEdge, barSize, scale) {
  var k = scale === undefined ? 1 : scale
  var box = { x: 0, y: 0, width: width, height: height }
  if (options.mode === "fill") return box
  var m = Math.max(options.spacing, options.frame ? FRAME_BORDER : 0) * k
  var bar = options.avoidBar ? Math.max(0, barSize || 0) * k : 0
  var left = m + (barEdge === "left" ? bar : 0)
  var top = m + (barEdge === "top" ? bar : 0)
  var right = m + (barEdge === "right" ? bar : 0)
  var bottom = m + (barEdge === "bottom" ? bar : 0)
  // Clamp excessive spacing on very small displays rather than flipping it.
  box = { x: Math.min(left, width / 2), y: Math.min(top, height / 2),
    width: Math.max(0, width - left - right), height: Math.max(0, height - top - bottom) }
  if (!(imageWidth > 0 && imageHeight > 0)) return box
  var fit = Math.min(box.width / imageWidth, box.height / imageHeight)
  var w = imageWidth * fit, h = imageHeight * fit
  return {
    x: Math.round(box.x + (box.width - w) / 2),
    y: Math.round(box.y + (box.height - h) / 2),
    width: Math.round(w), height: Math.round(h)
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
    FRAME_BORDER: FRAME_BORDER,
    MAX_SPACING: MAX_SPACING,
    MIN_HOURS: MIN_HOURS,
    MAX_HOURS: MAX_HOURS,
    appearance: appearance,
    normalize: normalize,
    appearanceFor: appearanceFor,
    withAppearance: withAppearance,
    needsImageColor: needsImageColor,
    placement: placement,
    nextChange: nextChange,
    duration: duration
  }
}
