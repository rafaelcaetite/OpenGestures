import Testing
@testable import OpenGesturesCore

struct ConfigurationTests {
    @Test func defaultConfigurationIsValidAndInert() throws {
        let configuration = try ConfigurationParser.parse(DefaultConfiguration.text)
        #expect(configuration.bindingCount == 0)
        #expect(configuration.warnings.isEmpty)
        #expect(configuration.settings == Settings())
    }

    @Test func readsGeneralSettings() throws {
        let configuration = try ConfigurationParser.parse("""
            [GENERAL]
            haptic-feedback = false
            dominant-hand = "left"
            tap-duration = 250
            slide-step = 4
            surprise = 1
            """)
        #expect(configuration.settings.hapticFeedback == false)
        #expect(configuration.settings.recognizer.dominantHand == .left)
        #expect(configuration.settings.recognizer.tapDuration == 0.25)
        #expect(configuration.settings.recognizer.slideStep == 4)
        #expect(configuration.warnings == ["line 6: unknown setting \"surprise\" ignored"])
    }

    @Test func rejectsOutOfRangeSettings() {
        #expect(throws: ConfigurationError.self) {
            try ConfigurationParser.parse("[GENERAL]\nslide-step = 0")
        }
    }

    @Test func resolvesApplicationScopesBeforeGlobalBindings() throws {
        let configuration = try ConfigurationParser.parse("""
            [TRACKPAD]
            three-finger-tap = "cmd+1"
            fn+three-finger-tap = "cmd+4"

            [TRACKPAD."!Terminal"]
            three-finger-tap = "cmd+2"

            [TRACKPAD."Safari, com.apple.mail"]
            three-finger-tap = "cmd+3"
            """)

        func resolve(_ name: String?, bundle: String? = nil, fn: Bool = false) -> String? {
            let application = name.map { ApplicationIdentity(name: $0, bundleIdentifier: bundle) }
            return configuration.binding(for: .threeFingerTap, device: .trackpad, application: application, functionKeyDown: fn)?.source
        }

        #expect(resolve("Safari") == "cmd+3")
        #expect(resolve("Mail", bundle: "com.apple.mail") == "cmd+3")
        #expect(resolve("Finder") == "cmd+2")
        #expect(resolve("Terminal") == "cmd+1")
        #expect(resolve("Terminal", fn: true) == "cmd+4")
        #expect(configuration.binding(for: .threeFingerTap, device: .mouse, application: nil, functionKeyDown: false) == nil)
    }

    @Test func parsesEveryBindingForm() throws {
        let configuration = try ConfigurationParser.parse("""
            [TRACKPAD]
            two-finger-tap = "mission-control"
            three-finger-tap = ["cmd+c", "wait:100", "url:https://example.com/?q={{clipboard|urlencode}}"]
            four-finger-tap = { action = "menu:File > New Window", haptic = false, sound = "Glass" }
            four-finger-slide = "volume"
            three-finger-slide = { preset = "tabs", step = 20 }
            hold-slide = { up = "cmd+=", down = "cmd+-" }
            """)
        let section = try #require(configuration.sections.first)

        guard case .action(let sequence) = section.binding(for: GestureKey(.threeFingerTap)) else {
            Issue.record("expected an action"); return
        }
        #expect(sequence.steps.count == 3)
        #expect(sequence.steps[1] == .wait(milliseconds: 100))

        guard case .action(let expanded) = section.binding(for: GestureKey(.fourFingerTap)) else {
            Issue.record("expected an action"); return
        }
        #expect(expanded.haptic == false)
        #expect(expanded.steps == [.playSound("Glass"), .menuCommand(["File", "New Window"])])

        guard case .slide(let volume) = section.binding(for: GestureKey(.fourFingerSlide)) else {
            Issue.record("expected a slide"); return
        }
        #expect(Set(volume.actions.keys) == [.up, .down])
        #expect(configuration.slideTarget(for: volume).step == 0.8)

        guard case .slide(let tabs) = section.binding(for: GestureKey(.threeFingerSlide)) else {
            Issue.record("expected a slide"); return
        }
        #expect(tabs.step == 20)
        #expect(Set(tabs.actions.keys) == [.left, .right])
    }

    @Test func suggestsTheClosestGestureName() {
        #expect(throws: ConfigurationError(
            line: 2,
            message: "unknown gesture \"four-finger-swip-up\"; did you mean \"four-finger-swipe-up\"?"
        )) {
            try ConfigurationParser.parse("[TRACKPAD]\nfour-finger-swip-up = \"cmd+a\"")
        }
    }

    @Test func rejectsGesturesTheDeviceCannotProduce() {
        #expect(throws: ConfigurationError.self) {
            try ConfigurationParser.parse("[MOUSE]\nfour-finger-slide = \"volume\"")
        }
        #expect(throws: ConfigurationError.self) {
            try ConfigurationParser.parse("[TRACKPAD]\none-finger-tap = \"return\"")
        }
    }

    @Test func rejectsDiscreteValuesForSlides() {
        #expect(throws: ConfigurationError.self) {
            try ConfigurationParser.parse("[TRACKPAD]\nfour-finger-slide = \"volume-up\"")
        }
    }

    @Test func reportsOverlapsWithMacOSGestures() throws {
        let configuration = try ConfigurationParser.parse("""
            [TRACKPAD]
            four-finger-slide = "volume"
            four-finger-swipe-left = "cmd+["
            three-finger-tap = "return"
            """)
        let preferences: [String: Int] = [
            "TrackpadFourFingerVertSwipeGesture": 0,
            "TrackpadFourFingerHorizSwipeGesture": 2,
            "TrackpadThreeFingerTapGesture": 2,
        ]
        let warnings = SystemGestures.conflicts(in: configuration) { preferences[$0] }
        #expect(warnings.count == 2)
        #expect(warnings.contains { $0.hasPrefix("line 3: four-finger-swipe-left") })
        #expect(warnings.contains { $0.hasPrefix("line 4: three-finger-tap") })
    }
}
