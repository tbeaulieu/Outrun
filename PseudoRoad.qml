import QtQuick 2.3
import QtQuick.Shapes 1.0
// If you're on Qt6, change the import above to just:
//   import QtQuick.Shapes

// Minimal pseudo-3D straight road strip for a dashboard.
// Single input: vehicleSpeed. No track, no curves, no user control.
// Road surface uses QtQuick.Shapes (GPU scene-graph geometry, NOT the
// software Canvas/QPainter path) so each segment is a real slanted
// trapezoid instead of a flat-sided rectangle -- that's what removes
// the "chunky staircase" look on the road edges.
//
// Layers, back to front:
//   sky -> base grass fill -> alternating grass bands -> road trapezoids -> roadside sprites -> traffic cars

Item {
    id: pseudoRoad

    // --- Public API ---------------------------------------------------
    property real vehicleSpeed: 0     // bind this to your real speed signal
    property real speedToScroll: 60.0  // feel/tuning knob

    // Night mode for sprites: swaps each sprite's source image to a
    // pre-made "night" version (if the def provides one) instead of
    // tinting at runtime. No shader cost -- it's just picking which
    // texture gets bound, same as any other source change.
    property bool nightMode: false

    // Roadside sprites. Each entry: { source, side, width, height, mirror,
    //                                 interval, offset, sideGap }.
    //   source:   a url/path to your .png
    //   side:     "left", "right", or a number (-1 = left, 1 = right)
    //             omit entirely to auto-alternate left/right
    //   width/height: optional per-sprite size at the nearest segment
    //             (scale = 1); falls back to spriteBaseWidth/spriteBaseHeight
    //   mirror:   optional bool override; default auto-mirrors on the left
    //   interval: optional -- how many segments between repeats of THIS
    //             sprite specifically. Smaller = more condensed/denser.
    //             Falls back to spriteInterval if omitted.
    //   offset:   optional phase shift (in segments) so this sprite's
    //             occurrences don't line up with segment 0 -- useful when
    //             mixing several densities so they don't all coincide.
    //   sideGap:  optional per-sprite distance from the road edge.
    //             Falls back to spriteSideGap if omitted.
    //   yOffset:  optional vertical nudge (pixels, at the nearest segment/
    //             scale 1). Positive moves the sprite DOWN, negative moves
    //             it UP. Falls back to spriteYOffset if omitted. Useful
    //             when a .png has empty padding at the bottom, making the
    //             object look like it's floating above the ground line.
    //   nightSource: optional url to a pre-made dark/silhouette version
    //             of this sprite. Used instead of "source" whenever
    //             nightMode is true. If omitted, falls back to "source"
    //             even in night mode (so you can convert art gradually).
    property var spriteDefs: []
    property real spriteBaseWidth: (86 * 6)    // fallback size if a def omits width
    property real spriteBaseHeight: (168 * 6)  // fallback size if a def omits height
    property int spriteInterval: 6             // default segment gap if a def omits interval
    property real spriteSideGap: 100           // default road-edge gap if a def omits sideGap
    property real spriteYOffset: 0             // default vertical nudge if a def omits yOffset
    property color skyColorTop: "#0092FB"          // top of the sky gradient
    property color skyColorBottom: "#8DCFFF"       // bottom of the sky
    property color roadColorOn: "#949494"          // road surface on "on" segments
    property color roadColorOff: "#9c9c9c"         // road surface on "off" segments
    property color terrainColorOn: "#efdece"       // grass/sand on "on" segments   
    property color terrainColorOff: "#e6d6c5"      // grass/sand on "off" segments

    // Traffic cars. Unlike spriteDefs (fixed points in the world that you
    // simply approach), each car has its OWN persistent world position
    // that advances every tick at its own speed -- so its apparent
    // distance depends on the gap between vehicleSpeed and the car's
    // speed, not on where it sits in the segment grid.
    //
    // Each entry: { source, nightSource, width, height, mirror, lane,
    //               speed, count }.
    //   source/nightSource/width/height/mirror: same meaning as spriteDefs.
    //             width/height fall back to trafficBaseWidth/trafficBaseHeight.
    //   lane:     "left", "center", "right", "random" (re-rolled every
    //             spawn/respawn), or a raw fraction of road width (e.g.
    //             0.2). Defaults to "center" if omitted.
    //   speed:    this car's own forward speed, in the SAME units as
    //             vehicleSpeed. speed < vehicleSpeed: you catch up and
    //             pass it. speed > vehicleSpeed: it pulls away toward the
    //             horizon. speed === vehicleSpeed: constant apparent gap,
    //             just like real highway traffic pacing you. Defaults to 0
    //             (a "stalled" car you always approach at your own speed).
    //   speedVariance: optional fraction (e.g. 0.15 = +/-15%). Each car
    //             instance gets its own randomized speed within this
    //             range, re-rolled on every respawn, so clones of the
    //             same def don't all move in lockstep.
    //   scalePercent: optional per-car size multiplier as a percentage
    //             (100 = normal size, 50 = half size, 150 = 1.5x).
    //             Applied on TOP of the normal distance-based perspective
    //             scale -- it doesn't replace it, just scales the whole
    //             car bigger/smaller at every distance. Falls back to
    //             trafficScalePercent if omitted.
    //   count:    how many simultaneous instances of this car to keep
    //             alive/cycling at once. Defaults to 1.
    property var trafficDefs: []
    property real trafficBaseWidth: (86 * 6)
    property real trafficBaseHeight: (168 * 6)
    property real trafficYOffset: 0
    property real trafficScalePercent: 100   // 100 = normal size; default if a def omits scalePercent
    // Below this perspective scale (near the horizon), a car is hidden
    // entirely instead of rendering as a barely-visible speck. Raise this
    // if cars still seem to "hang around" too long near the horizon;
    // lower it if they're disappearing too abruptly/early.
    property real trafficMinScale: 0.05
    // How much random distance-jitter gets added when a car respawns at
    // the far edge, on top of maxVisibleZ. Wider range = less obviously
    // "on a cycle."
    property real trafficRespawnJitter: segmentLength * 10

    // Cloud cover layer: a horizontally-tiling image that continuously
    // drifts left-to-right, independent of vehicleSpeed (clouds move
    // whether the car is stopped or not). For a seamless loop, the
    // source image's left and right edges should match up visually --
    // otherwise you'll see a faint seam once per loop.
    property url cloudSource: ""                   // leave empty to disable
    property real cloudWidth: width                // on-screen width of ONE tile
    property real cloudHeight: height * 0.16
    property real cloudTopOffset: height * 0.07
    property real cloudSpeed: 40                    // px/sec, positive = left-to-right
    property real cloudLayerOpacity: 0.9
    property url secondLayerSource: ""  //Second background layer
    property real secondLayerWidth: 1536
    // --------------------------------------------------------------------

    //Horizon stripe image
    property url horizonStripeSource: ""

    // Total pooled sprite slots needed: each def gets its own worst-case
    // simultaneous count based on ITS OWN interval, summed together.
    readonly property int spriteSlotCount: computeSpriteSlotCount()
    function computeSpriteSlotCount() {
        var total = 0
        for (var k = 0; k < spriteDefs.length; k++) {
            var iv = (spriteDefs[k].interval !== undefined) ? spriteDefs[k].interval : spriteInterval
            total += Math.ceil(numLines / Math.max(iv, 1)) + 1
        }
        return total
    }

    // Total pooled traffic-car slots: sum of each def's requested count
    // (defaulting to 1 if omitted).
    readonly property int trafficSlotCount: computeTrafficSlotCount()
    function computeTrafficSlotCount() {
        var total = 0
        for (var k = 0; k < trafficDefs.length; k++) {
            total += (trafficDefs[k].count !== undefined) ? trafficDefs[k].count : 1
        }
        return total
    }

    readonly property int numLines: 80
    readonly property real horizonY: height * 0.42
    property string laneMarkingColor: "#ffffff"
    property real laneMarkingWidthNear: 35
    property bool showLaneDividers: true

    // Edge lines running along the road's outer boundary. Unlike the
    // center dividers (which toggle visibility on/off for a dash), these
    // stay visible every segment and instead toggle POSITION: "on"
    // segments get pushed inward by their own width, "off" segments sit
    // flush against the true edge -- giving the classic alternating
    // in/out "curb" look.
    property bool showEdgeLines: true
    property string edgeMarkingColor: laneMarkingColor
    property real edgeMarkingWidthNear: 40

    // zNear = world distance of the closest segment (bottom of screen).
    // roadWidthNear = pixel width of the road at that closest segment.
    // These are just "feel" constants -- tune to taste.
    readonly property real zNear: 300.0
    readonly property real roadWidthNear: width * 2.7
    readonly property real segmentLength: 200.0

    // Furthest world distance our segment table actually covers -- used
    // as the traffic spawn/cull boundary so cars appear/disappear right
    // around the horizon instead of popping in mid-screen.
    readonly property real maxVisibleZ: zNear + numLines * segmentLength

    property real position: 0

    // Worst case: half the segments show a dash (alternating on/off),
    // times 2 divider lines (left + right).
    readonly property int laneDividerSlotCount: numLines + 4

    // Edge lines are visible on EVERY segment (no dash gaps), on both
    // sides -- so exactly numLines * 2 are needed each frame.
    readonly property int edgeLineSlotCount: numLines * 2 + 2

    // Internal: live traffic car state (worldZ + lane per active car).
    // Rebuilt whenever trafficDefs changes.
    property var _trafficState: []

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: skyColorTop }
            GradientStop { position: 0.33; color: skyColorBottom }
        }
    }

    // Drifting cloud cover. Two copies of the source image placed
    // back-to-back, continuously animated from x=-cloudWidth to x=0 and
    // looping -- reads as one endless band crawling left to right.
    // Uses a plain NumberAnimation (not the JS update loop) since this
    // should keep drifting even when vehicleSpeed is 0.
    Item {
        id: cloudClip
        x: 0
        y: pseudoRoad.cloudTopOffset
        width: pseudoRoad.width
        height: pseudoRoad.cloudHeight
        clip: true
        visible: pseudoRoad.cloudSource != ""
        opacity: pseudoRoad.cloudLayerOpacity
        Row{
            id:backImage
            x: -pseudoRoad.secondLayerWidth
            y:-25
            Image{
                source: pseudoRoad.secondLayerSource
            }
            Image{
                source: pseudoRoad.secondLayerSource
            }
            NumberAnimation on x {
                running: pseudoRoad.secondLayerSource != "" && pseudoRoad.cloudSpeed !== 0
                from: -pseudoRoad.secondLayerWidth
                to: 0
                duration: Math.abs(pseudoRoad.secondLayerWidth / Math.max(pseudoRoad.cloudSpeed, 0.001)) * 1500
                loops: Animation.Infinite
            }
        }
        Row {
            id: cloudRow
            x: -pseudoRoad.cloudWidth

            Image {
                width: pseudoRoad.cloudWidth
                height: pseudoRoad.cloudHeight
                source: pseudoRoad.cloudSource
                fillMode: Image.Stretch
            }
            Image {
                width: pseudoRoad.cloudWidth
                height: pseudoRoad.cloudHeight
                source: pseudoRoad.cloudSource
                fillMode: Image.Stretch
            }

            NumberAnimation on x {
                running: pseudoRoad.cloudSource != "" && pseudoRoad.cloudSpeed !== 0
                from: -pseudoRoad.cloudWidth
                to: 0
                duration: Math.abs(pseudoRoad.cloudWidth / Math.max(pseudoRoad.cloudSpeed, 0.001)) * 1000
                loops: Animation.Infinite
            }
        }
        
    }
    Image{
        id: horizonStripe
        source: horizonStripeSource
        x: 0; y: 256; z: 1
    }
    Repeater {
        id: grassStrips
        model: pseudoRoad.numLines
        delegate: Rectangle { }
    }

    // Road surface: one Shape per segment, each holding a single
    // trapezoid (near-left, near-right, far-right, far-left). Because
    // consecutive segments share an exact edge (this one's "far" pair
    // equals the next one's "near" pair), the whole road reads as one
    // continuous slanted edge instead of a stack of steps.
    Repeater {
        id: strips
        model: pseudoRoad.numLines
        delegate: Shape {
            id: seg
            x: 0
            y: 0
            width: pseudoRoad.width
            height: pseudoRoad.height
            antialiasing: true

            property real nearY: 0
            property real farY: 0
            property real nearHalfW: 0
            property real farHalfW: 0
            property real centerX: pseudoRoad.width / 2
            property color fillColor: "#b0b0b0"

            ShapePath {
                fillColor: seg.fillColor
                strokeWidth: -1   // no outline -- avoids a visible seam between segments
                startX: seg.centerX - seg.nearHalfW; startY: seg.nearY
                PathLine { x: seg.centerX + seg.nearHalfW; y: seg.nearY }
                PathLine { x: seg.centerX + seg.farHalfW;  y: seg.farY }
                PathLine { x: seg.centerX - seg.farHalfW;  y: seg.farY }
                PathLine { x: seg.centerX - seg.nearHalfW; y: seg.nearY }
            }
        }
    }

    // Dashed lane dividers: same tapering trapezoid trick as the road,
    // just narrow and offset from center. Pooled like sprites -- only
    // shown on segments where the dash is "on", hidden otherwise.
    Repeater {
        id: laneDividers
        model: pseudoRoad.laneDividerSlotCount
        delegate: Shape {
            id: dseg
            x: 0
            y: 0
            width: pseudoRoad.width
            height: pseudoRoad.height
            antialiasing: true
            visible: false

            property real nearY: 0
            property real farY: 0
            property real nearHalfW: 0
            property real farHalfW: 0
            property real nearCenterX: 0
            property real farCenterX: 0
            property color fillColor: pseudoRoad.laneMarkingColor

            ShapePath {
                fillColor: dseg.fillColor
                strokeWidth: -1
                startX: dseg.nearCenterX - dseg.nearHalfW; startY: dseg.nearY
                PathLine { x: dseg.nearCenterX + dseg.nearHalfW; y: dseg.nearY }
                PathLine { x: dseg.farCenterX + dseg.farHalfW;  y: dseg.farY }
                PathLine { x: dseg.farCenterX - dseg.farHalfW;  y: dseg.farY }
                PathLine { x: dseg.nearCenterX - dseg.nearHalfW; y: dseg.nearY }
            }
        }
    }

    // Edge lines: same tapering trapezoid trick, but always visible --
    // they toggle POSITION (in/out) each segment instead of visibility.
    Repeater {
        id: edgeLines
        model: pseudoRoad.edgeLineSlotCount
        delegate: Shape {
            id: eseg
            x: 0
            y: 0
            width: pseudoRoad.width
            height: pseudoRoad.height
            antialiasing: true
            visible: false

            property real nearY: 0
            property real farY: 0
            property real nearHalfW: 0
            property real farHalfW: 0
            property real nearCenterX: 0
            property real farCenterX: 0
            property color fillColor: pseudoRoad.edgeMarkingColor

            ShapePath {
                fillColor: eseg.fillColor
                strokeWidth: -1
                startX: eseg.nearCenterX - eseg.nearHalfW; startY: eseg.nearY
                PathLine { x: eseg.nearCenterX + eseg.nearHalfW; y: eseg.nearY }
                PathLine { x: eseg.farCenterX + eseg.farHalfW;  y: eseg.farY }
                PathLine { x: eseg.farCenterX - eseg.farHalfW;  y: eseg.farY }
                PathLine { x: eseg.nearCenterX - eseg.nearHalfW; y: eseg.nearY }
            }
        }
    }

    Repeater {
        id: sprites
        model: pseudoRoad.spriteSlotCount
        delegate: Image {
            visible: false
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
    }

    // Traffic cars: same pooled Image approach as sprites, but positioned
    // every frame from _trafficState's persistent worldZ rather than
    // being derived from the segment loop.
    Repeater {
        id: trafficCars
        model: pseudoRoad.trafficSlotCount
        delegate: Image {
            visible: false
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
    }

    // Projects one world distance z to a screen Y and a 0..1 scale factor.
    // scale = zNear/z: 1 at the closest segment, shrinking toward 0 with
    // distance -- this 1/z falloff is what makes screenY bunch up near
    // the horizon instead of spacing out evenly, and what sprites use to
    // shrink/converge as they "approach" from the horizon.
    function project(z) {
        var scale = zNear / z
        var screenY = horizonY + (height - horizonY) * scale
        return { screenY: screenY, scale: scale }
    }

    // Resolves a spriteDefs[].side entry to -1 (left) or 1 (right).
    // Accepts "left"/"right", a raw number, or omission (auto-alternate
    // based on how many times this def has been placed so far).
    function resolveSide(def, placementIndex) {
        if (typeof def.side === "number") return def.side
        if (def.side === "left") return -1
        if (def.side === "right") return 1
        return (placementIndex % 2 === 0) ? -1 : 1
    }

    // Resolves whether a placed sprite should be horizontally mirrored.
    // If the def specifies "mirror" explicitly, that always wins.
    // Otherwise, default to mirroring on the left side -- most sprite art
    // (trees, signs) is drawn facing one direction, and flipping it for
    // the opposite side of the road is the classic pseudo-3D-racer trick.
    function resolveMirror(def, side) {
        if (def.mirror !== undefined) return def.mirror
        return side === -1
    }

    // Resolves a trafficDefs[].lane entry to a fraction of the road's
    // half-width: -1/3 = left lane center, 0 = center lane, 1/3 = right
    // lane center (matching the 3-equal-lanes math used for edge lines
    // and dividers elsewhere in this file). "random" picks one of the
    // three each time this is called (spawn and every respawn). A raw
    // number is used as-is.
    function resolveLaneFrac(def) {
        if (typeof def.lane === "number") return def.lane
        if (def.lane === "left") return -1 / 3
        if (def.lane === "right") return 1 / 3
        if (def.lane === "random") {
            var options = [-1 / 3, 0, 1 / 3]
            return options[Math.floor(Math.random() * options.length)]
        }
        return 0   // "center" or omitted
    }

    // Resolves a car's actual speed for this spawn, applying speedVariance
    // (if the def specifies one) as a one-time random roll rather than a
    // per-frame fluctuation -- each car keeps a consistent pace for the
    // duration of its pass, then gets a fresh roll on its next respawn.
    function resolveCarSpeed(def) {
        var base = (def.speed !== undefined) ? def.speed : 0
        var variance = def.speedVariance
        if (!variance) return base
        var jitter = (Math.random() * 2 - 1) * variance
        return base * (1 + jitter)
    }

    // (Re)builds the persistent traffic car state from trafficDefs.
    // Spreads each def's cars out RANDOMLY across the visible depth (not
    // evenly) so they don't spawn looking obviously arranged.
    function initTraffic() {
        var state = []
        for (var k = 0; k < trafficDefs.length; k++) {
            var def = trafficDefs[k]
            var count = (def.count !== undefined) ? def.count : 1
            for (var c = 0; c < count; c++) {
                var spread = zNear + Math.random() * maxVisibleZ
                state.push({
                    defIndex: k,
                    worldZ: position + spread,
                    laneFrac: resolveLaneFrac(def),
                    speed: resolveCarSpeed(def)
                })
            }
        }
        _trafficState = state
    }

    onTrafficDefsChanged: initTraffic()

    function updateTraffic() {
        var dtSeconds = 16 / 1000
        var slot0 = 0

        for (var k = 0; k < _trafficState.length; k++) {
            var car = _trafficState[k]
            var def = trafficDefs[car.defIndex]
            if (!def) continue

            car.worldZ += car.speed * speedToScroll * dtSeconds

            var relZ = car.worldZ - position

            // Recycle: either passed behind the camera, or drifted too
            // far ahead to matter -- respawn at the far edge of the
            // visible range so traffic keeps cycling indefinitely.
            // Lane and speed get re-rolled here too, so a car doesn't
            // repeat the exact same lane/pace every single pass.
            if (relZ < zNear * 0.6 || relZ > maxVisibleZ * 1.05) {
                car.worldZ = position + maxVisibleZ + Math.random() * trafficRespawnJitter
                car.laneFrac = resolveLaneFrac(def)
                car.speed = resolveCarSpeed(def)
                relZ = car.worldZ - position
            }

            var slot = trafficCars.itemAt(slot0)
            slot0++
            if (!slot) continue

            if (relZ < zNear * 0.6) {
                slot.visible = false
                continue
            }

            var p = project(relZ)

            // Hide entirely once it's shrunk down near the horizon --
            // otherwise it lingers forever as a barely-visible dot instead
            // of actually vanishing.
            if (p.scale < trafficMinScale) {
                slot.visible = false
                continue
            }

            var scaleMult = ((def.scalePercent !== undefined) ? def.scalePercent : trafficScalePercent) / 100
            var baseW = (def.width !== undefined) ? def.width : trafficBaseWidth
            var baseH = (def.height !== undefined) ? def.height : trafficBaseHeight
            var sw = Math.max(baseW * p.scale * scaleMult, 1)
            var sh = Math.max(baseH * p.scale * scaleMult, 1)
            var yOff = (def.yOffset !== undefined) ? def.yOffset : trafficYOffset
            var centerX = width / 2 + car.laneFrac * roadWidthNear * p.scale

            slot.source = (nightMode && def.nightSource !== undefined) ? def.nightSource : def.source
            slot.mirror = (def.mirror !== undefined) ? def.mirror : false
            slot.width = sw
            slot.height = sh
            slot.x = centerX - sw / 2
            slot.y = p.screenY - sh + yOff * p.scale * scaleMult
            slot.visible = true

            // Same depth-based z trick as roadside sprites: map relZ onto
            // the same j-equivalent scale so cars and trees/signs sort
            // correctly against each other, not just against other cars.
            var jEquiv = (relZ - zNear) / segmentLength
            jEquiv = Math.max(0, Math.min(numLines, jEquiv))
            slot.z = (numLines - jEquiv) + 1
        }

        for (; slot0 < trafficSlotCount; slot0++) {
            var unusedCar = trafficCars.itemAt(slot0)
            if (unusedCar) unusedCar.visible = false
        }
    }

    function updateStrips() {
        // `position` grows forever as the vehicle drives -- wrap it back
        // down periodically rather than let it climb unbounded for the
        // life of the dashboard. The wrap chunk is a multiple of
        // segmentLength AND divisible by every small interval (1-16),
        // so baseIndex's parity/modulo behavior (road stripes, lane
        // dividers, and any spriteDefs interval up to 16) comes out
        // exactly the same on the other side of the wrap -- no visible
        // hitch. If you ever use a sprite interval that doesn't divide
        // 720720, there's a theoretical one-frame glitch right at the
        // wrap instant, which happens roughly once every wrapChunk
        // world-units of driving (practically: extremely rare).
        if (position > 50000000) {
            var wrapChunk = segmentLength * 720720
            position -= Math.floor(position / wrapChunk) * wrapChunk
        }

        var scrollOffset = position % segmentLength
        var baseIndex = Math.floor(position / segmentLength)

        // Sample one segment boundary further than we draw, so every
        // visible strip can compute its far edge from the next sample.
        var samples = []
        for (var i = 0; i <= numLines; i++) {
            var z = zNear + i * segmentLength - scrollOffset
            samples.push(project(z))
        }

        var spriteSlot = 0
        var dividerSlot = 0
        var edgeSlot = 0

        for (var j = 0; j < numLines; j++) {
            var near = samples[j]
            var far = samples[j + 1]
            var stripeOn = (baseIndex + j) % 2 === 0
            var stripHeight = Math.max(near.screenY - far.screenY, 1)
            var roadColor = stripeOn ? roadColorOn : roadColorOff
            var terrainColor = stripeOn ? terrainColorOn : terrainColorOff
            // grass/sand band: full width, flat rectangle is fine here since
            // there's no side-taper to smooth -- it spans the full width
            var g = grassStrips.itemAt(j)
            if (g) {
                g.x = 0
                g.y = far.screenY
                g.width = width
                g.height = stripHeight
                g.color = terrainColor
            }

            // road trapezoid: near edge at this segment's screenY/width,
            // far edge at the next segment's -- gives a real slanted side
            var seg = strips.itemAt(j)
            if (seg) {
                seg.nearY = near.screenY
                seg.farY = far.screenY
                seg.nearHalfW = Math.max(roadWidthNear * near.scale, 1) / 2
                seg.farHalfW = Math.max(roadWidthNear * far.scale, 1) / 2
                seg.fillColor = roadColor
            }

            // dashed lane dividers: reuse the road's own on/off banding as
            // the dash rhythm, so the dashes move at exactly the same
            // pace as the road surface stripes
            if (showLaneDividers && stripeOn) {
                var sides = [-1, 1]
                for (var s = 0; s < 2; s++) {
                    var dSide = sides[s]
                    var dSlot = laneDividers.itemAt(dividerSlot)
                    dividerSlot++
                    if (dSlot) {
                        var nearRoadW = roadWidthNear * near.scale
                        var farRoadW = roadWidthNear * far.scale

                        dSlot.nearCenterX = width / 2 + dSide * (nearRoadW / 6)
                        dSlot.farCenterX = width / 2 + dSide * (farRoadW / 6)
                        dSlot.nearHalfW = Math.max(laneMarkingWidthNear * near.scale, 0.5) / 2
                        dSlot.farHalfW = Math.max(laneMarkingWidthNear * far.scale, 0.5) / 2
                        dSlot.nearY = near.screenY
                        dSlot.farY = far.screenY
                        dSlot.visible = true
                    }
                }
            }

            // edge lines: always visible (no gaps), but the on/off flag
            // now controls POSITION instead of visibility -- "on" pushes
            // the line inward by its own width, "off" sits flush right
            // against the true road edge, giving an alternating curb look
            if (showEdgeLines) {
                var edgeSides = [-1, 1]
                for (var e = 0; e < 2; e++) {
                    var eSide = edgeSides[e]
                    var eSlot = edgeLines.itemAt(edgeSlot)
                    edgeSlot++
                    if (eSlot) {
                        var nearEdgeGap = (roadWidthNear * near.scale) / 2
                        var farEdgeGap = (roadWidthNear * far.scale) / 2
                        var nearHalf = Math.max(edgeMarkingWidthNear * near.scale, 0.5) / 2
                        var farHalf = Math.max(edgeMarkingWidthNear * far.scale, 0.5) / 2
                        var nearFullW = nearHalf * 2
                        var farFullW = farHalf * 2

                        // "off": outer face of the line sits flush at the
                        // true edge, extending inward by its half-width
                        var nearFlush = eSide * (nearEdgeGap - nearHalf)
                        var farFlush = eSide * (farEdgeGap - farHalf)
                        // "on": pushed inward one additional full width
                        var nearPushed = nearFlush - eSide * nearFullW
                        var farPushed = farFlush - eSide * farFullW

                        eSlot.nearCenterX = width / 2 + (stripeOn ? nearPushed : nearFlush)
                        eSlot.farCenterX = width / 2 + (stripeOn ? farPushed : farFlush)
                        eSlot.nearHalfW = nearHalf
                        eSlot.farHalfW = farHalf
                        eSlot.nearY = near.screenY
                        eSlot.farY = far.screenY
                        eSlot.visible = true
                    }
                }
            }

            // roadside sprites: each def is checked independently against
            // its OWN interval/offset, so a dense "condensed" sprite (e.g.
            // water reeds every 2 segments) and a sparse one (e.g. trees
            // every 6) can coexist without one forcing the other's rhythm
            for (var d = 0; d < spriteDefs.length; d++) {
                var def = spriteDefs[d]
                var interval = (def.interval !== undefined) ? def.interval : spriteInterval
                var phase = def.offset !== undefined ? def.offset : 0

                if ((baseIndex + j + phase) % Math.max(interval, 1) !== 0) continue

                var slot = sprites.itemAt(spriteSlot)
                spriteSlot++
                if (!slot) continue

                var placementIndex = Math.floor((baseIndex + j + phase) / Math.max(interval, 1))
                var side = resolveSide(def, placementIndex)
                var mirror = resolveMirror(def, side)
                var gap = (def.sideGap !== undefined) ? def.sideGap : spriteSideGap
                var yOff = (def.yOffset !== undefined) ? def.yOffset : spriteYOffset
                var baseW = (def.width !== undefined) ? def.width : spriteBaseWidth
                var baseH = (def.height !== undefined) ? def.height : spriteBaseHeight
                var sw = Math.max(baseW * near.scale, 1)
                var sh = Math.max(baseH * near.scale, 1)
                var centerX = width / 2 + side * (roadWidthNear / 2 + gap) * near.scale

                slot.source = (nightMode && def.nightSource !== undefined) ? def.nightSource : def.source
                slot.mirror = mirror
                slot.width = sw
                slot.height = sh
                slot.x = centerX - sw / 2
                slot.y = near.screenY - sh + yOff * near.scale
                slot.visible = true
                // Nearer segments (small j) must always paint over farther
                // ones, regardless of which def or pool slot placed them --
                // pool-slot order alone doesn't reflect depth, so we set
                // z explicitly. +1 keeps every sprite above the road/grass/
                // divider layers (which sit at the default z of 0).
                slot.z = (numLines - j) + 1
            }
        }

        // hide any pooled sprite slots we didn't use this frame
        for (; spriteSlot < spriteSlotCount; spriteSlot++) {
            var unused = sprites.itemAt(spriteSlot)
            if (unused) unused.visible = false
        }

        // hide any pooled divider slots we didn't use this frame
        for (; dividerSlot < laneDividerSlotCount; dividerSlot++) {
            var unusedDivider = laneDividers.itemAt(dividerSlot)
            if (unusedDivider) unusedDivider.visible = false
        }

        // hide any pooled edge-line slots we didn't use this frame
        for (; edgeSlot < edgeLineSlotCount; edgeSlot++) {
            var unusedEdge = edgeLines.itemAt(edgeSlot)
            if (unusedEdge) unusedEdge.visible = false
        }
    }

    Component.onCompleted: {
        initTraffic()
        updateStrips()
    }

    Timer {
        interval: 16
        running: pseudoRoad.vehicleSpeed > 0
        repeat: true
        onTriggered: {
            pseudoRoad.position += pseudoRoad.vehicleSpeed * (pseudoRoad.speedToScroll * 16 / 1000)
            pseudoRoad.updateStrips()
        }
    }

    // Traffic runs on its OWN timer, independent of vehicleSpeed. A car's
    // worldZ advances at its own pace regardless of whether the player is
    // moving -- so cars with speed > 0 correctly keep driving away into
    // the horizon even while you're sitting still.
    Timer {
        interval: 16
        running: pseudoRoad.trafficDefs.length > 0
        repeat: true
        onTriggered: pseudoRoad.updateTraffic()
    }
}
