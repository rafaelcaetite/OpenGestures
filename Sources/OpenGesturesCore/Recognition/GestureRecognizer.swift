import Foundation

/// The recognizer's view of the active configuration.
///
/// Recognition depends on what is bound in three places: a single tap waits
/// for a possible double tap only when the double tap is bound, a movement
/// becomes a slide only when the slide is bound, and holds and brushes are
/// only reported when bound so they never swallow an ordinary tap.
public protocol GestureBindings {
    func isBound(_ gesture: Gesture) -> Bool
    func slide(for gesture: Gesture) -> SlideTarget?
}

/// What a bound slide reacts to.
public struct SlideTarget: Equatable, Sendable {
    public var directions: Set<Direction>
    /// Distance in millimetres between two consecutive steps.
    public var step: Double

    public init(directions: Set<Direction>, step: Double) {
        self.directions = directions
        self.step = step
    }
}

public enum RecognizedGesture: Equatable, Sendable {
    case gesture(Gesture)
    case slide(Gesture, Direction)
}

public struct RecognizerSettings: Equatable, Sendable {
    /// Longest time a finger may stay down and still count as a tap.
    public var tapDuration: TimeInterval = 0.30
    /// Farthest a finger may travel, in millimetres, and still count as a tap.
    public var tapTravel: Double = 3.0
    /// Fingers of one tap must all land within this window.
    public var landingWindow: TimeInterval = 0.15
    public var doubleTapInterval: TimeInterval = 0.30
    /// A held finger must land at least this long before the tapping finger.
    public var holdLead: TimeInterval = 0.12
    public var holdTravel: Double = 4.0
    /// Movement in millimetres before a gesture commits to an axis.
    public var motionThreshold: Double = 3.0
    /// Movement before a bound slide starts. Lower than `motionThreshold`
    /// so a slide reacts at once; a slide already suppresses taps.
    public var slideThreshold: Double = 1.0
    public var swipeDistance: Double = 18.0
    public var slideStep: Double = 5.0
    public var brushMinimumSpan: TimeInterval = 0.08
    public var brushMaximumSpan: TimeInterval = 0.60
    public var dominantHand: Hand = .right

    public init() {}
}

/// Turns the contact frames of one device into gestures.
///
/// A session starts when the first finger lands and ends when the last one
/// lifts. Discrete gestures that depend on the whole session (taps, brushes)
/// are decided when it ends; holds, swipes and slides are decided while it is
/// in progress. The recognizer is not thread-safe; feed it from one queue.
public final class GestureRecognizer {
    public let device: DeviceKind
    public var settings: RecognizerSettings

    private struct Track {
        var id: Int32
        var landedAt: TimeInterval
        var start: Point
        var current: Point
        var travel: Double
    }

    private struct Lift {
        var landedAt: TimeInterval
        var liftedAt: TimeInterval
        var start: Point
        var travel: Double
    }

    private enum MotionPhase {
        case pending
        case swipe(Axis)
        case slide(Gesture, SlideTarget, Axis, anchor: Double)
        case finished
        case ignored
    }

    private struct MotionFamily {
        var slide: Gesture?
        var swipeFingers: Int?
    }

    private struct Motion {
        var fingers: Int
        var origin: Point
        /// Position in the previous frame, to carry a slide across a change
        /// in the number of fingers.
        var last: Point
        var family: MotionFamily
        var phase: MotionPhase
    }

    private struct PendingTap {
        var fingers: Int
        var time: TimeInterval
        var token: Int
    }

    // Small arrays rather than sets or dictionaries: a hand has at most ten
    // fingers, and frames arrive about a hundred times a second, so linear
    // scans over reused storage beat hashing and avoid per-frame allocation.
    private var tracks: [Track] = []
    private var lifts: [Lift] = []
    private var maxFingers = 0
    private var suppressTaps = false
    private var motion: Motion?
    private var pendingTap: PendingTap?
    private var nextToken = 0

    public init(device: DeviceKind, settings: RecognizerSettings = RecognizerSettings()) {
        self.device = device
        self.settings = settings
        tracks.reserveCapacity(12)
        lifts.reserveCapacity(12)
    }

    /// Identifies a single tap held back while waiting for a possible double
    /// tap. Pass it to `resolvePendingTap(token:)` once the interval elapses.
    public var pendingTapToken: Int? { pendingTap?.token }

    public var isSessionActive: Bool { !tracks.isEmpty }

    /// True while a slide is running, from its first step until every finger
    /// has lifted.
    public var isSliding: Bool {
        if case .slide = motion?.phase { return true }
        return false
    }

    public func process(_ frame: TouchFrame, bindings: GestureBindings) -> [RecognizedGesture] {
        if tracks.isEmpty && frame.touches.isEmpty {
            return []
        }
        var output: [RecognizedGesture] = []
        let now = frame.timestamp

        var index = 0
        while index < tracks.count {
            let track = tracks[index]
            if frame.touches.contains(where: { $0.id == track.id }) {
                index += 1
                continue
            }
            tracks.remove(at: index)
            let lift = Lift(landedAt: track.landedAt, liftedAt: now, start: track.start, travel: track.travel)
            lifts.append(lift)
            if !suppressMotionHolds, let hold = holdTap(for: lift, bindings: bindings) {
                output.append(.gesture(hold))
                suppressTaps = true
            }
        }

        for touch in frame.touches {
            if let existing = tracks.firstIndex(where: { $0.id == touch.id }) {
                tracks[existing].current = touch.position
                tracks[existing].travel = max(tracks[existing].travel, tracks[existing].start.distance(to: touch.position))
            } else {
                tracks.append(Track(id: touch.id, landedAt: now, start: touch.position, current: touch.position, travel: 0))
            }
        }
        maxFingers = max(maxFingers, tracks.count)

        if tracks.isEmpty {
            if !lifts.isEmpty {
                output += finishSession(at: now, bindings: bindings)
            }
            resetSession()
        } else {
            output += updateMotion(bindings: bindings)
        }
        return output
    }

    /// Reports the single tap held back for `token`, unless a second tap has
    /// already turned it into a double tap.
    public func resolvePendingTap(token: Int) -> [RecognizedGesture] {
        guard let pending = pendingTap, pending.token == token else { return [] }
        pendingTap = nil
        return Gesture.tap(fingers: pending.fingers).map { [.gesture($0)] } ?? []
    }

    /// Stops the current session from producing anything further. Used when
    /// a physical click has already been handled as a gesture.
    public func suppressCurrentSession() {
        guard isSessionActive else { return }
        suppressTaps = true
        motion?.phase = .finished
    }

    // MARK: - Session

    private var suppressMotionHolds: Bool {
        if case .slide = motion?.phase { return true }
        if case .finished = motion?.phase { return true }
        return false
    }

    private func resetSession() {
        tracks.removeAll(keepingCapacity: true)
        lifts.removeAll(keepingCapacity: true)
        maxFingers = 0
        suppressTaps = false
        motion = nil
    }

    private func finishSession(at now: TimeInterval, bindings: GestureBindings) -> [RecognizedGesture] {
        guard !suppressTaps, lifts.count == maxFingers else { return [] }
        guard lifts.allSatisfy({ $0.travel <= settings.tapTravel }) else { return [] }

        if let brush = brush(bindings: bindings) {
            return [.gesture(brush)]
        }

        let landings = lifts.map(\.landedAt)
        guard let firstLanding = landings.min(), let lastLanding = landings.max(),
              lastLanding - firstLanding <= settings.landingWindow,
              lifts.allSatisfy({ $0.liftedAt - $0.landedAt <= settings.tapDuration })
        else { return [] }

        return registerTap(fingers: lifts.count, at: now, bindings: bindings)
    }

    private func registerTap(fingers: Int, at now: TimeInterval, bindings: GestureBindings) -> [RecognizedGesture] {
        var output: [RecognizedGesture] = []
        let doubleTap = Gesture.doubleTap(fingers: fingers)

        if let pending = pendingTap {
            pendingTap = nil
            if pending.fingers == fingers, now - pending.time <= settings.doubleTapInterval, let doubleTap {
                return [.gesture(doubleTap)]
            }
            if let single = Gesture.tap(fingers: pending.fingers) {
                output.append(.gesture(single))
            }
        }

        if let doubleTap, bindings.isBound(doubleTap) {
            nextToken += 1
            pendingTap = PendingTap(fingers: fingers, time: now, token: nextToken)
        } else if let single = Gesture.tap(fingers: fingers) {
            output.append(.gesture(single))
        }
        return output
    }

    // MARK: - Holds and brushes

    private func holdTap(for lift: Lift, bindings: GestureBindings) -> Gesture? {
        guard lift.liftedAt - lift.landedAt <= settings.tapDuration, lift.travel <= settings.tapTravel else {
            return nil
        }
        let held = tracks
        guard (1...3).contains(held.count),
              held.allSatisfy({ $0.landedAt <= lift.landedAt - settings.holdLead && $0.travel <= settings.holdTravel }),
              let leftmost = held.map(\.current.x).min(),
              let rightmost = held.map(\.current.x).max()
        else { return nil }

        let x = lift.start.x
        let gesture: Gesture?
        switch held.count {
        case 1:
            gesture = x > rightmost ? .holdLeftTapRight : .holdRightTapLeft
        case 2:
            gesture = x > rightmost ? .holdTwoTapRight : x < leftmost ? .holdTwoTapLeft : .holdTwoTapBetween
        default:
            gesture = x > rightmost ? .holdThreeTapRight : x < leftmost ? .holdThreeTapLeft : nil
        }
        guard let gesture, bindings.isBound(gesture) else { return nil }
        return gesture
    }

    private func brush(bindings: GestureBindings) -> Gesture? {
        guard device == .trackpad, lifts.count == 4 else { return nil }
        let ordered = lifts.sorted { $0.landedAt < $1.landedAt }
        guard let first = ordered.first, let last = ordered.last,
              let lastLift = lifts.map(\.liftedAt).max()
        else { return nil }

        let span = last.landedAt - first.landedAt
        guard span >= settings.brushMinimumSpan, span <= settings.brushMaximumSpan,
              lastLift - first.landedAt <= settings.brushMaximumSpan + settings.tapDuration
        else { return nil }

        let xs = ordered.map(\.start.x)
        let pairs = zip(xs, xs.dropFirst())
        let leftToRight = pairs.allSatisfy { $0 < $1 }
        let rightToLeft = pairs.allSatisfy { $0 > $1 }
        guard leftToRight || rightToLeft else { return nil }

        // With the right hand the index finger is the leftmost of the four.
        let indexFirst = leftToRight == (settings.dominantHand == .right)
        let gesture: Gesture = indexFirst ? .indexToPinky : .pinkyToIndex
        return bindings.isBound(gesture) ? gesture : nil
    }

    // MARK: - Swipes and slides

    private func motionFamily(fingers: Int) -> MotionFamily? {
        switch (device, fingers) {
        case (.trackpad, 2): return holdSlideDriver() == nil ? MotionFamily() : MotionFamily(slide: .holdSlide)
        case (.trackpad, 3): return MotionFamily(slide: .threeFingerSlide, swipeFingers: 3)
        case (.trackpad, 4): return MotionFamily(slide: .fourFingerSlide, swipeFingers: 4)
        case (.mouse, 1): return MotionFamily(swipeFingers: 1)
        case (.mouse, 2): return MotionFamily(slide: .twoFingerSlide, swipeFingers: 2)
        case (_, 0): return nil
        default: return MotionFamily()
        }
    }

    /// For a hold-slide, the finger that moves: the later of two, landing
    /// while the earlier one was already resting and still.
    private func holdSlideDriver() -> Track? {
        guard tracks.count == 2 else { return nil }
        let (held, driver) = tracks[0].landedAt <= tracks[1].landedAt ? (tracks[0], tracks[1]) : (tracks[1], tracks[0])
        guard driver.landedAt - held.landedAt >= settings.holdLead, held.travel <= settings.holdTravel else {
            return nil
        }
        return driver
    }

    private func motionPosition(fingers: Int, family: MotionFamily) -> Point {
        if family.slide == .holdSlide, let driver = holdSlideDriver() {
            return driver.current
        }
        let sum = tracks.reduce(Point.zero) { $0 + $1.current }
        return Point(x: sum.x / Double(fingers), y: sum.y / Double(fingers))
    }

    private func updateMotion(bindings: GestureBindings) -> [RecognizedGesture] {
        let fingers = tracks.count
        guard var current = motion else {
            startMotion(fingers: fingers)
            return []
        }

        if current.fingers != fingers {
            // A running slide survives a finger slipping off or landing late:
            // the anchor moves with the jump in the centroid, so the change in
            // fingers produces no steps and the slide carries on without
            // waiting for a new threshold.
            guard case .slide(let gesture, let target, let axis, let anchor) = current.phase, fingers > 0 else {
                startMotion(fingers: fingers)
                return []
            }
            current.fingers = fingers
            let position = motionPosition(fingers: fingers, family: current.family)
            let jump = (position - current.last).component(along: axis)
            current.phase = .slide(gesture, target, axis, anchor: anchor + jump)
            current.last = position
            motion = current
            return []
        }

        let position = motionPosition(fingers: fingers, family: current.family)
        let output = advance(&current, position: position, bindings: bindings)
        current.last = position
        motion = current
        return output
    }

    private func startMotion(fingers: Int) {
        guard let family = motionFamily(fingers: fingers) else {
            motion = nil
            return
        }
        let origin = motionPosition(fingers: fingers, family: family)
        motion = Motion(fingers: fingers, origin: origin, last: origin, family: family, phase: .pending)
    }

    private func advance(_ motion: inout Motion, position: Point, bindings: GestureBindings) -> [RecognizedGesture] {
        let delta = position - motion.origin

        switch motion.phase {
        case .pending:
            let distance = max(abs(delta.x), abs(delta.y))
            guard distance >= min(settings.slideThreshold, settings.motionThreshold) else { return [] }
            let axis: Axis = abs(delta.x) > abs(delta.y) ? .horizontal : .vertical
            let direction = Direction.along(axis, positive: delta.component(along: axis) > 0)

            if let slide = motion.family.slide, let target = bindings.slide(for: slide),
               target.directions.contains(where: { $0.axis == axis }) {
                motion.phase = .slide(slide, target, axis, anchor: motion.origin.component(along: axis))
                suppressTaps = true
            } else if distance < settings.motionThreshold {
                return []
            } else if let fingers = motion.family.swipeFingers,
                      [Gesture.swipe(fingers: fingers, direction: direction), Gesture.swipe(fingers: fingers)]
                          .compactMap({ $0 }).contains(where: bindings.isBound) {
                motion.phase = .swipe(axis)
            } else {
                motion.phase = .ignored
                return []
            }
            return advance(&motion, position: position, bindings: bindings)

        case .swipe(let axis):
            let distance = delta.component(along: axis)
            guard abs(distance) >= settings.swipeDistance, let fingers = motion.family.swipeFingers else { return [] }
            motion.phase = .finished
            suppressTaps = true
            let direction = Direction.along(axis, positive: distance > 0)
            let candidates = [Gesture.swipe(fingers: fingers, direction: direction), Gesture.swipe(fingers: fingers)]
            return candidates.compactMap { $0 }.first(where: bindings.isBound).map { [.gesture($0)] } ?? []

        case .slide(let gesture, let target, let axis, var anchor):
            guard target.step > 0 else { return [] }
            var output: [RecognizedGesture] = []
            let value = position.component(along: axis)
            let forward = Direction.along(axis, positive: true)
            let backward = Direction.along(axis, positive: false)
            while value - anchor >= target.step {
                anchor += target.step
                if target.directions.contains(forward) { output.append(.slide(gesture, forward)) }
            }
            while anchor - value >= target.step {
                anchor -= target.step
                if target.directions.contains(backward) { output.append(.slide(gesture, backward)) }
            }
            motion.phase = .slide(gesture, target, axis, anchor: anchor)
            return output

        case .finished, .ignored:
            return []
        }
    }
}
