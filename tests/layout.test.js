const test = require("node:test")
const assert = require("node:assert/strict")
const Layout = require("../Layout.js")
const fit = (patch = {}) => Layout.appearance({ mode: "fit", ...patch })
const place = (options, edge = "top", scale = 1) =>
  Layout.placement(options, 5120 * scale, 1440 * scale, 1600, 1000, edge, 26, scale)

test("normalize repairs hand-edited settings and survives repeated normalization", () => {
  assert.deepEqual(Layout.normalize(null), {
    mode: "fill", background: "blur", frame: false, spacing: 0, avoidBar: false,
    frameColor: "", backgroundColor: "", displays: {}, cycleHours: 0, shuffle: false
  })
  const settings = Layout.normalize({
    mode: "stretch", background: "unknown", spacing: 5000, frame: "yes",
    displays: { "DP-3": "framed", "DP-1": "tiled", bad: null },
    frameColor: "#abcdef", backgroundColor: "red", cycleHours: 500, shuffle: "yes"
  })
  assert.equal(settings.mode, "fill")
  assert.equal(settings.background, "blur")
  assert.equal(settings.spacing, Layout.MAX_SPACING)
  assert.equal(settings.frame, false)
  assert.deepEqual(Object.keys(settings.displays), ["DP-3"])
  assert.equal(settings.frameColor, "#ABCDEF")
  assert.equal(settings.backgroundColor, "")
  assert.equal(settings.cycleHours, Layout.MAX_HOURS)
  assert.equal(settings.shuffle, false)
  assert.deepEqual(Layout.normalize(settings), settings)
  assert.equal(Layout.normalize({ cycleHours: -2, spacing: -1 }).spacing, 0)
  assert.equal(Layout.normalize({ spacing: "no" }).spacing, 0)
})

test("old presets and global colors migrate without changing their appearance", () => {
  const settings = Layout.normalize({ preset: "framed", frameColor: "#abcdef",
    edgeColor: "#123456", displays: { laptop: "fill", wide: "extend" }, cycleHours: 4 })
  assert.deepEqual(Layout.appearanceFor(settings, "other"), fit({
    frame: true, spacing: 24, avoidBar: true, frameColor: "#ABCDEF", backgroundColor: "#123456"
  }))
  assert.equal(Layout.appearanceFor(settings, "laptop").mode, "fill")
  const wide = Layout.appearanceFor(settings, "wide")
  assert.equal(wide.background, "color")
  assert.equal(wide.backgroundColor, "#123456")
  assert.equal(wide.frame, false)
  assert.equal(wide.spacing, 0)
  assert.equal(wide.avoidBar, false)
  assert.equal(Layout.normalize({ preset: "extend" }).background, "image")
  assert.equal(settings.cycleHours, 4)
  assert.deepEqual(Layout.normalize(JSON.parse(JSON.stringify(settings))), settings)
  const oldFramed = place(Layout.appearanceFor(settings, "other"))
  assert.equal(oldFramed.y, 24 + 26)
  assert.equal(oldFramed.height, 1440 - 48 - 26)
})

test("display edits keep independent options, and all displays clears overrides", () => {
  let settings = Layout.normalize({ cycleHours: 2, shuffle: true })
  settings = Layout.withAppearance(settings, "DP-3", { mode: "fit", background: "image", spacing: 32 })
  settings = Layout.withAppearance(settings, "DP-3", { frame: true })
  assert.deepEqual(Layout.appearanceFor(settings, "DP-3"), fit({ background: "image", spacing: 32, frame: true }))
  assert.equal(Layout.appearanceFor(settings, "DP-1").mode, "fill")
  settings = Layout.withAppearance(settings, "DP-3", { mode: "fill" })
  settings = Layout.withAppearance(settings, "DP-3", { mode: "fit" })
  assert.equal(Layout.appearanceFor(settings, "DP-3").spacing, 32)
  settings = Layout.withAppearance(settings, "", { mode: "fit", background: "color", backgroundColor: "#778899" })
  assert.deepEqual(settings.displays, {})
  assert.equal(Layout.appearanceFor(settings, "DP-3").backgroundColor, "#778899")
  assert.equal(settings.cycleHours, 2)
  assert.equal(settings.shuffle, true)
})

test("background color sampling is only needed by Fit with Image color", () => {
  let settings = Layout.normalize({ mode: "fill", background: "image" })
  assert.equal(Layout.needsImageColor(settings), false)
  settings = Layout.withAppearance(settings, "wide", { mode: "fit" })
  assert.equal(Layout.needsImageColor(settings), true)
  settings = Layout.withAppearance(settings, "wide", { background: "color" })
  assert.equal(Layout.needsImageColor(settings), false)
})

test("Fill covers the screen and Fit contains the whole image", () => {
  assert.deepEqual(place(Layout.appearance({ frame: true, spacing: 80, avoidBar: true })),
    { x: 0, y: 0, width: 5120, height: 1440 })
  assert.deepEqual(place(fit()), { x: 1408, y: 0, width: 2304, height: 1440 })
  assert.deepEqual(Layout.placement(fit(), 100, 50, 0, 0, "top", 26),
    { x: 0, y: 0, width: 100, height: 50 })
  // Portrait image on a landscape screen, and the reverse.
  for (const [sw, sh, iw, ih] of [[1920, 1080, 900, 1600], [1080, 1920, 1600, 900]]) {
    const rect = Layout.placement(fit(), sw, sh, iw, ih, "top", 26)
    assert.ok(rect.x >= 0 && rect.y >= 0)
    assert.ok(rect.x + rect.width <= sw && rect.y + rect.height <= sh)
    assert.ok(Math.abs(rect.width / rect.height - iw / ih) < 0.002)
  }
})

test("background and frame do not force spacing or bar clearance", () => {
  for (const background of ["blur", "image", "color"]) {
    assert.deepEqual(place(fit({ background, spacing: 24 })), place(fit({ background, frame: true, spacing: 24 })))
    assert.deepEqual(place(fit({ background })), place(fit()))
    const framed = place(fit({ background, frame: true }))
    assert.equal(framed.y, Layout.FRAME_BORDER)
    assert.equal(framed.height, 1440 - 2 * Layout.FRAME_BORDER)
  }
})

test("spacing and bar clearance work independently on all bar edges and in thumbnails", () => {
  for (const edge of ["top", "bottom", "left", "right"]) {
    const options = fit({ spacing: 24, avoidBar: true })
    const rect = place(options, edge)
    assert.equal(Math.round(rect.x + rect.width / 2), 2560 + (edge === "left" ? 13 : edge === "right" ? -13 : 0))
    assert.equal(Math.round(rect.y + rect.height / 2), 720 + (edge === "top" ? 13 : edge === "bottom" ? -13 : 0))
    const thumb = place(options, edge, 0.1)
    for (const key of ["x", "y", "width", "height"]) assert.ok(Math.abs(thumb[key] - rect[key] * 0.1) <= 1)
  }
  const tiny = Layout.placement(fit({ spacing: 256, avoidBar: true }), 100, 50, 1600, 900, "left", 26)
  assert.ok(tiny.width >= 0 && tiny.height >= 0 && tiny.x >= 0 && tiny.y >= 0)
})

test("cycling counts from the last change", () => {
  const settings = Layout.normalize({ cycleHours: 2 })
  assert.equal(Layout.nextChange(settings, 1000), 1000 + 2 * 3600 * 1000)
  assert.equal(Layout.nextChange(Layout.normalize({}), 1000), 0)
  assert.equal(Layout.duration(125 * 60000), "2 h 5 min")
  assert.equal(Layout.duration(40 * 60000), "40 min")
  assert.equal(Layout.duration(-5), "under a minute")
})
