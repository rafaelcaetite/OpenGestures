import Foundation

/// Finds bindings whose gesture macOS also responds to.
///
/// OpenGestures only observes the trackpad; it cannot stop macOS from acting
/// on the same movement. When both respond, both actions run, so overlaps are
/// reported as warnings.
public enum SystemGestures {
    private struct Rule {
        var key: String
        var feature: String
        var gestures: Set<Gesture>
        var slideAxes: [Gesture: Axis]
        /// Settings that must also be on for the rule to apply.
        var requires: [String] = []
        /// Settings that, when on, mean the feature uses another motion.
        var unless: [String] = []
    }

    private static let domains = [
        "com.apple.AppleMultitouchTrackpad",
        "com.apple.driver.AppleBluetoothMultitouch.trackpad",
    ]

    private static func swipes(_ fingers: Int, _ axis: Axis) -> Set<Gesture> {
        let directions = Direction.allCases.filter { $0.axis == axis }
        return Set(directions.compactMap { Gesture.swipe(fingers: fingers, direction: $0) } + [Gesture.swipe(fingers: fingers)].compactMap { $0 })
    }

    private static let rules: [Rule] = [
        Rule(key: "TrackpadThreeFingerTapGesture", feature: "Look up & data detectors",
             gestures: [.threeFingerTap], slideAxes: [:]),
        Rule(key: "TrackpadTwoFingerDoubleTapGesture", feature: "Smart zoom",
             gestures: [.twoFingerDoubleTap], slideAxes: [:]),
        Rule(key: "TrackpadRightClick", feature: "Secondary click with two fingers",
             gestures: [.twoFingerTap], slideAxes: [:],
             requires: ["Clicking"], unless: ["TrackpadCornerSecondaryClick"]),
        Rule(key: "TrackpadThreeFingerDrag", feature: "Three finger drag",
             gestures: swipes(3, .horizontal).union(swipes(3, .vertical)),
             slideAxes: [.threeFingerSlide: .horizontal]),
        Rule(key: "TrackpadThreeFingerDrag", feature: "Three finger drag",
             gestures: [], slideAxes: [.threeFingerSlide: .vertical]),
        Rule(key: "TrackpadThreeFingerHorizSwipeGesture", feature: "Swipe between pages or full-screen apps with three fingers",
             gestures: swipes(3, .horizontal), slideAxes: [.threeFingerSlide: .horizontal]),
        Rule(key: "TrackpadThreeFingerVertSwipeGesture", feature: "Mission Control and App Exposé with three fingers",
             gestures: swipes(3, .vertical), slideAxes: [.threeFingerSlide: .vertical]),
        Rule(key: "TrackpadFourFingerHorizSwipeGesture", feature: "Swipe between full-screen apps with four fingers",
             gestures: swipes(4, .horizontal), slideAxes: [.fourFingerSlide: .horizontal]),
        Rule(key: "TrackpadFourFingerVertSwipeGesture", feature: "Mission Control and App Exposé with four fingers",
             gestures: swipes(4, .vertical), slideAxes: [.fourFingerSlide: .vertical]),
        Rule(key: "TrackpadFourFingerPinchGesture", feature: "Launchpad and Show Desktop pinch",
             gestures: [.indexToPinky, .pinkyToIndex], slideAxes: [:]),
        Rule(key: "TrackpadFiveFingerPinchGesture", feature: "Launchpad and Show Desktop pinch",
             gestures: [.indexToPinky, .pinkyToIndex], slideAxes: [:]),
    ]

    public static func conflicts(
        in configuration: Configuration,
        preference: (String) -> Int? = readPreference
    ) -> [String] {
        var warnings: [String] = []
        var reported: Set<String> = []
        for section in configuration.sections where section.device == .trackpad {
            for entry in section.entries {
                for feature in overlaps(entry.key.gesture, binding: entry.binding, preference: preference) {
                    let id = "\(entry.key.name)|\(feature)"
                    guard !reported.contains(id) else { continue }
                    reported.insert(id)
                    warnings.append(
                        "line \(entry.line): \(entry.key.name) overlaps the macOS gesture \"\(feature)\"; "
                            + "turn it off in System Settings > Trackpad or both will run"
                    )
                }
            }
        }
        return warnings
    }

    /// The macOS features, by their System Settings names, that also respond
    /// when `gesture` is bound to `binding` on the trackpad.
    public static func overlaps(
        _ gesture: Gesture,
        binding: Binding,
        preference: (String) -> Int? = readPreference
    ) -> [String] {
        func isOn(_ key: String) -> Bool { (preference(key) ?? 0) != 0 }

        var features: [String] = []
        for rule in rules where isOn(rule.key)
            && rule.requires.allSatisfy(isOn)
            && !rule.unless.contains(where: isOn) {
            var overlaps = rule.gestures.contains(gesture)
            if case .slide(let slide) = binding, let axis = rule.slideAxes[gesture] {
                overlaps = overlaps || slide.actions.keys.contains { $0.axis == axis }
            }
            if overlaps, !features.contains(rule.feature) {
                features.append(rule.feature)
            }
        }
        return features
    }

    public static func readPreference(_ key: String) -> Int? {
        var result: Int?
        for domain in domains {
            if let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Int {
                result = max(result ?? 0, value)
            }
        }
        return result
    }
}
