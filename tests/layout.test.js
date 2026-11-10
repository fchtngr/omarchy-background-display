const test = require("node:test")
const assert = require("node:assert/strict")
const Layout = require("../Layout.js")

test("normalize repairs a hand-edited file", () => {
  assert.deepEqual(Layout.normalize(null), {
    preset: "fill", displays: {}, frameColor: "", edgeColor: "", cycleHours: 0, shuffle: false
  })
  const settings = Layout.normalize({
    preset: "stretch", displays: { "DP-3": "framed", "DP-1": "tiled" },
    frameColor: "#abcdef", edgeColor: "red", cycleHours: 500, shuffle: "yes"
  })
  assert.equal(settings.preset, "fill")
  assert.deepEqual(settings.displays, { "DP-3": "framed" })
  assert.equal(settings.frameColor, "#ABCDEF")
  assert.equal(settings.edgeColor, "")
  assert.equal(settings.cycleHours, Layout.MAX_HOURS)
  assert.equal(settings.shuffle, false)
  assert.equal(Layout.normalize({ cycleHours: -2 }).cycleHours, 0)
})

test("a display's own preset wins, and every display clears them", () => {
  let settings = Layout.withPreset(Layout.normalize({}), "DP-3", "framed")
  assert.equal(Layout.presetFor(settings, "DP-3"), "framed")
  assert.equal(Layout.presetFor(settings, "DP-1"), "fill")
  settings = Layout.withPreset(settings, "", "extend")
  assert.deepEqual(settings.displays, {})
  assert.equal(Layout.presetFor(settings, "DP-3"), "extend")
})

test("placement fits whole images and keeps framed clear of the bar", () => {
  // A 16:10 image on a 32:9 screen.
  assert.deepEqual(Layout.placement("fill", 5120, 1440, 1600, 1000, "top", 26),
    { x: 0, y: 0, width: 5120, height: 1440 })
  assert.deepEqual(Layout.placement("extend", 5120, 1440, 1600, 1000, "top", 26),
    { x: 1408, y: 0, width: 2304, height: 1440 })
  const framed = Layout.placement("framed", 5120, 1440, 1600, 1000, "top", 26)
  assert.equal(framed.y, Layout.FRAME_MARGIN + 26)
  assert.equal(framed.height, 1440 - 2 * Layout.FRAME_MARGIN - 26)
  assert.equal(Math.round(framed.x + framed.width / 2), 2560)
  // Scaled down for a thumbnail, the margin and the bar shrink with it.
  const thumb = Layout.placement("framed", 512, 144, 1600, 1000, "top", 26, 0.1)
  assert.equal(thumb.y, Math.round(0.1 * (Layout.FRAME_MARGIN + 26)))
  // Size unknown yet: the space the preset may use.
  assert.deepEqual(Layout.placement("extend", 100, 50, 0, 0, "top", 26), { x: 0, y: 0, width: 100, height: 50 })
})

test("cycling counts from the last change", () => {
  const settings = Layout.normalize({ cycleHours: 2 })
  assert.equal(Layout.nextChange(settings, 1000), 1000 + 2 * 3600 * 1000)
  assert.equal(Layout.nextChange(Layout.normalize({}), 1000), 0)
  assert.equal(Layout.duration(125 * 60000), "2 h 5 min")
  assert.equal(Layout.duration(40 * 60000), "40 min")
  assert.equal(Layout.duration(-5), "under a minute")
})
