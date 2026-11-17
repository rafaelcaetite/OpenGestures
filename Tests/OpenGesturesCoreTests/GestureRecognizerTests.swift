import Testing
@testable import OpenGesturesCore

private struct StubBindings: GestureBindings {
    var bound: Set<Gesture> = []
    var slides: [Gesture: SlideTarget] = [:]

    func isBound(_ gesture: Gesture) -> Bool {
        bound.contains(gesture) || slides[gesture] != nil
    }

    func slide(for gesture: Gesture) -> SlideTarget? {
        slides[gesture]
    }
}

/// Feeds a recognizer frames built from finger positions in millimetres.
private final class Harness {
    let recognizer: GestureRecognizer
    var bindings: StubBindings
    var output: [RecognizedGesture] = []

    init(device: DeviceKind = .trackpad, bindings: StubBindings) {
        recognizer = GestureRecognizer(device: device)
        self.bindings = bindings
    }

    func frame(_ time: Double, _ fingers: [(Int32, Double, Double)]) {
        let touches = fingers.map { id, x, y in
            Touch(id: id, position: Point(x: x, y: y), normalized: Point(x: x / 100, y: y / 100))
        }
        output += recognizer.process(TouchFrame(timestamp: time, touches: touches), bindings: bindings)
    }

    func tap(fingers: Int, at time: Double) {
        let points: [(Int32, Double, Double)] = (0..<fingers).map { index in
            (Int32(index + 1), 20 + Double(index) * 15, 40)
        }
        frame(time, points)
        frame(time + 0.08, points)
        frame(time + 0.12, [])
    }

    /// Moves `fingers` fingers together from `start` by `delta` over `steps` frames.
    func move(fingers: Int, from start: Point, by delta: Point, steps: Int = 10, at time: Double = 0) {
        for step in 0...steps {
            let fraction = Double(step) / Double(steps)
            let y: Double = start.y + delta.y * fraction
            var points: [(Int32, Double, Double)] = []
            for index in 0..<fingers {
                let x: Double = start.x + Double(index) * 15 + delta.x * fraction
                points.append((Int32(index + 1), x, y))
            }
            frame(time + Double(step) * 0.01, points)
        }
        frame(time + Double(steps + 1) * 0.01, [])
    }
}

struct GestureRecognizerTests {
    @Test func recognizesMultiFingerTaps() {
        let harness = Harness(bindings: StubBindings(bound: [.threeFingerTap]))
        harness.tap(fingers: 3, at: 0)
        #expect(harness.output == [.gesture(.threeFingerTap)])
    }

    @Test func holdsBackASingleTapOnlyWhenADoubleTapIsBound() throws {
        let harness = Harness(bindings: StubBindings(bound: [.twoFingerTap, .twoFingerDoubleTap]))
        harness.tap(fingers: 2, at: 0)
        #expect(harness.output.isEmpty)
        let token = try #require(harness.recognizer.pendingTapToken)
        #expect(harness.recognizer.resolvePendingTap(token: token) == [.gesture(.twoFingerTap)])

        harness.tap(fingers: 2, at: 1.0)
        harness.tap(fingers: 2, at: 1.2)
        #expect(harness.output == [.gesture(.twoFingerDoubleTap)])
        #expect(harness.recognizer.pendingTapToken == nil)
    }

    @Test func doesNotTreatALongPressAsATap() {
        let harness = Harness(bindings: StubBindings(bound: [.threeFingerTap]))
        let points: [(Int32, Double, Double)] = [(1, 10, 10), (2, 25, 10), (3, 40, 10)]
        harness.frame(0, points)
        harness.frame(0.5, points)
        harness.frame(0.6, [])
        #expect(harness.output.isEmpty)
    }

    @Test func slidesFireOneStepPerDistance() {
        let target = SlideTarget(directions: [.up, .down], step: 5)
        let harness = Harness(bindings: StubBindings(slides: [.fourFingerSlide: target]))
        harness.move(fingers: 4, from: Point(x: 20, y: 20), by: Point(x: 0, y: 23))
        #expect(harness.output == Array(repeating: .slide(.fourFingerSlide, .up), count: 4))

        harness.output.removeAll()
        harness.move(fingers: 4, from: Point(x: 20, y: 60), by: Point(x: 1, y: -11), at: 1)
        #expect(harness.output == Array(repeating: .slide(.fourFingerSlide, .down), count: 2))
    }

    @Test func slidesRespondWithinAMillimetre() {
        let target = SlideTarget(directions: [.up, .down], step: 0.8)
        let harness = Harness(bindings: StubBindings(slides: [.fourFingerSlide: target]))
        let start: [(Int32, Double, Double)] = [(1, 15, 30), (2, 30, 30), (3, 45, 30), (4, 60, 30)]
        harness.frame(0.00, start)
        harness.frame(0.01, [(1, 15, 30.5), (2, 30, 30.5), (3, 45, 30.5), (4, 60, 30.5)])
        #expect(harness.output.isEmpty)
        harness.frame(0.02, [(1, 15, 31.1), (2, 30, 31.1), (3, 45, 31.1), (4, 60, 31.1)])
        #expect(harness.output == [.slide(.fourFingerSlide, .up)])
        #expect(harness.recognizer.isSliding)
    }

    @Test func slidesSurviveAFingerSlippingOff() {
        let target = SlideTarget(directions: [.up, .down], step: 1)
        let harness = Harness(bindings: StubBindings(slides: [.fourFingerSlide: target]))
        // Fingers in a slanted row, so dropping one moves the centroid a lot.
        func hand(_ y: Double, fingers: Int = 4) -> [(Int32, Double, Double)] {
            var points: [(Int32, Double, Double)] = []
            for finger in 1...fingers {
                let offset = Double(finger)
                points.append((Int32(finger), offset * 15, y + offset * 6))
            }
            return points
        }
        harness.frame(0.00, hand(20))
        harness.frame(0.01, hand(25))
        #expect(harness.output.count == 5)

        harness.output.removeAll()
        harness.frame(0.02, hand(25, fingers: 3))
        #expect(harness.output.isEmpty)
        harness.frame(0.03, hand(28, fingers: 3))
        #expect(harness.output == Array(repeating: .slide(.fourFingerSlide, .up), count: 3))

        harness.output.removeAll()
        harness.frame(0.04, hand(28))
        harness.frame(0.05, hand(26))
        #expect(harness.output == Array(repeating: .slide(.fourFingerSlide, .down), count: 2))
    }

    @Test func aStillTapIsNotASlide() {
        let target = SlideTarget(directions: [.up, .down], step: 0.8)
        let harness = Harness(bindings: StubBindings(bound: [.fourFingerTap], slides: [.fourFingerSlide: target]))
        let start: [(Int32, Double, Double)] = [(1, 15, 30), (2, 30, 30), (3, 45, 30), (4, 60, 30)]
        harness.frame(0.00, start)
        harness.frame(0.05, [(1, 15.3, 30.4), (2, 30.3, 30.4), (3, 45.3, 30.4), (4, 60.3, 30.4)])
        harness.frame(0.10, [])
        #expect(harness.output == [.gesture(.fourFingerTap)])
    }

    @Test func slidesIgnoreTheAxisTheyAreNotBoundTo() {
        let target = SlideTarget(directions: [.up, .down], step: 5)
        let harness = Harness(bindings: StubBindings(slides: [.fourFingerSlide: target]))
        harness.move(fingers: 4, from: Point(x: 10, y: 40), by: Point(x: 40, y: 2))
        #expect(harness.output.isEmpty)
    }

    @Test func swipesFireOnceInTheirDirection() {
        let harness = Harness(bindings: StubBindings(bound: [.threeFingerSwipeLeft]))
        harness.move(fingers: 3, from: Point(x: 60, y: 40), by: Point(x: -30, y: 3))
        #expect(harness.output == [.gesture(.threeFingerSwipeLeft)])
    }

    @Test func fallsBackToTheAnyDirectionSwipe() {
        let harness = Harness(bindings: StubBindings(bound: [.fourFingerSwipe]))
        harness.move(fingers: 4, from: Point(x: 20, y: 60), by: Point(x: 0, y: -25))
        #expect(harness.output == [.gesture(.fourFingerSwipe)])
    }

    @Test func recognizesHoldAndTap() {
        let harness = Harness(bindings: StubBindings(bound: [.holdLeftTapRight, .holdRightTapLeft]))
        harness.frame(0.0, [(1, 30, 30)])
        harness.frame(0.2, [(1, 30, 30)])
        harness.frame(0.3, [(1, 30, 30), (2, 55, 32)])
        harness.frame(0.4, [(1, 30, 30)])
        harness.frame(0.6, [(1, 30, 30), (3, 10, 30)])
        harness.frame(0.7, [(1, 30, 30)])
        harness.frame(0.9, [])
        #expect(harness.output == [.gesture(.holdLeftTapRight), .gesture(.holdRightTapLeft)])
    }

    @Test func holdSlideFollowsTheMovingFinger() {
        let target = SlideTarget(directions: [.up, .down], step: 5)
        let harness = Harness(bindings: StubBindings(slides: [.holdSlide: target]))
        harness.frame(0.0, [(1, 20, 20)])
        harness.frame(0.2, [(1, 20, 20), (2, 50, 20)])
        harness.frame(0.3, [(1, 20, 20), (2, 50, 31)])
        harness.frame(0.4, [])
        #expect(harness.output == [.slide(.holdSlide, .up), .slide(.holdSlide, .up)])
    }

    @Test(arguments: [(Hand.right, Gesture.indexToPinky), (Hand.left, Gesture.pinkyToIndex)])
    func recognizesBrushesByHand(hand: Hand, expected: Gesture) {
        var settings = RecognizerSettings()
        settings.dominantHand = hand
        let harness = Harness(bindings: StubBindings(bound: [.indexToPinky, .pinkyToIndex]))
        harness.recognizer.settings = settings
        harness.frame(0.00, [(1, 10, 30)])
        harness.frame(0.05, [(1, 10, 30), (2, 25, 30)])
        harness.frame(0.10, [(1, 10, 30), (2, 25, 30), (3, 40, 30)])
        harness.frame(0.15, [(1, 10, 30), (2, 25, 30), (3, 40, 30), (4, 55, 30)])
        harness.frame(0.25, [])
        #expect(harness.output == [.gesture(expected)])
    }

    @Test func idleFramesProduceNothing() {
        let harness = Harness(bindings: StubBindings(bound: Set(Gesture.allCases)))
        for index in 0..<100 {
            harness.frame(Double(index) * 0.01, [])
        }
        #expect(harness.output.isEmpty)
        #expect(!harness.recognizer.isSessionActive)
    }
}

struct ClickClassifierTests {
    private func touch(_ x: Double, _ y: Double) -> Touch {
        Touch(id: 1, position: Point(x: x * 100, y: y * 100), normalized: Point(x: x, y: y))
    }

    @Test func ordersCornerCandidatesFromMostSpecific() {
        let candidates = ClickClassifier.candidates(for: [touch(0.98, 0.02)], edgeSize: 0.15)
        #expect(Array(candidates.prefix(2)) == [.bottomRightCornerClick, .cornerClick])
        #expect(candidates.last == .edgeClick)
    }

    @Test func usesThirdsAndHalvesAlongTheEdge() {
        let candidates = ClickClassifier.candidates(for: [touch(0.05, 0.5)], edgeSize: 0.15)
        #expect(candidates == [.leftEdgeMiddleThirdClick, .leftEdgeTopHalfClick, .leftEdgeClick, .edgeClick])
    }

    @Test func ignoresTheCentre() {
        #expect(ClickClassifier.candidates(for: [touch(0.5, 0.5)], edgeSize: 0.15).isEmpty)
    }

    @Test func countsFingersForMultiFingerClicks() {
        let three = [touch(0.3, 0.5), touch(0.4, 0.5), touch(0.5, 0.5)]
        #expect(ClickClassifier.candidates(for: three, edgeSize: 0.15) == [.threeFingerClick])
    }
}
