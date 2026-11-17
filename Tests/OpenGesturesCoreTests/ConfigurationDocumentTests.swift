import Testing
@testable import OpenGesturesCore

struct ConfigurationDocumentTests {
    private let sample = """
        [GENERAL]
        haptic-feedback = true      # Tap the trackpad

        [TRACKPAD]

        # Continuous: slide four fingers.
        four-finger-slide = "volume"   # louder and quieter
        three-finger-tap = [
          "cmd+c",
          "wait:100",
        ]

        [TRACKPAD."Safari"]
        four-finger-slide = "tabs"

        [MOUSE]
        """

    @Test func replacesAValueAndKeepsItsComment() {
        var document = ConfigurationDocument(text: sample)
        document.set("four-finger-slide", to: "\"brightness\"", in: "TRACKPAD")
        #expect(document.text.contains("four-finger-slide = \"brightness\"   # louder and quieter"))
        #expect(document.text.contains("[TRACKPAD.\"Safari\"]\nfour-finger-slide = \"tabs\""))
        #expect(document.text.contains("# Continuous: slide four fingers."))
    }

    @Test func replacesAValueThatSpansLines() throws {
        var document = ConfigurationDocument(text: sample)
        document.set("three-finger-tap", to: "\"play-pause\"", in: "TRACKPAD")
        #expect(!document.text.contains("wait:100"))
        let configuration = try ConfigurationParser.parse(document.text)
        let binding = configuration.binding(for: .threeFingerTap, device: .trackpad, application: nil, functionKeyDown: false)
        #expect(binding?.source == "play-pause")
    }

    @Test func removesAKey() throws {
        var document = ConfigurationDocument(text: sample)
        document.set("three-finger-tap", to: nil, in: "TRACKPAD")
        document.set("four-finger-slide", to: nil, in: "TRACKPAD")
        let configuration = try ConfigurationParser.parse(document.text)
        #expect(configuration.sections.map(\.entries.count) == [0, 1, 0])
    }

    @Test func insertsAfterTheLastKeyOfTheSection() throws {
        var document = ConfigurationDocument(text: sample)
        document.set("two-finger-tap", to: "\"middle-click\"", in: "MOUSE")
        document.set("four-finger-tap", to: "\"mission-control\"", in: "TRACKPAD")
        #expect(document.text.contains("  \"wait:100\",\n]\nfour-finger-tap = \"mission-control\"\n"))
        #expect(document.text.hasSuffix("[MOUSE]\ntwo-finger-tap = \"middle-click\""))
        _ = try ConfigurationParser.parse(document.text)
    }

    @Test func appendsAMissingSection() throws {
        var document = ConfigurationDocument(text: "[GENERAL]\nhaptic-feedback = true\n")
        document.set("four-finger-slide", to: "\"volume\"", in: "TRACKPAD")
        #expect(document.text == "[GENERAL]\nhaptic-feedback = true\n\n[TRACKPAD]\nfour-finger-slide = \"volume\"\n")
        document.set("dominant-hand", to: "\"left\"", in: "GENERAL")
        let configuration = try ConfigurationParser.parse(document.text)
        #expect(configuration.settings.recognizer.dominantHand == .left)
    }

    @Test func ignoresHashesInsideStrings() {
        var document = ConfigurationDocument(text: "[TRACKPAD]\nfour-finger-tap = \"url:https://a.b/#top\" # note\n")
        document.set("four-finger-tap", to: "\"mute\"", in: "TRACKPAD")
        #expect(document.text == "[TRACKPAD]\nfour-finger-tap = \"mute\" # note\n")
    }
}

struct BindingDraftTests {
    private func value(_ toml: String) throws -> TOMLValue? {
        try TOMLParser.parse("key = \(toml)")["key"]
    }

    @Test func decodesCommonActions() throws {
        #expect(ActionDraft(try value("\"play-pause\"")) == .builtIn(.playPause))
        #expect(ActionDraft(try value("\"cmd+shift+4\"")) == .shortcut("cmd+shift+4"))
        #expect(ActionDraft(try value("\"app:com.apple.Safari\"")) == .application("com.apple.Safari"))
        #expect(ActionDraft(try value("\"https://example.com\"")) == .url("https://example.com"))
        #expect(ActionDraft(try value("\"text:hello\"")) == .text("hello"))
        #expect(ActionDraft(nil) == .none)
    }

    @Test func keepsEverythingElseAsWritten() throws {
        #expect(ActionDraft(try value("[\"cmd+c\", \"wait:50\"]")) == .custom("[\"cmd+c\", \"wait:50\"]"))
        #expect(ActionDraft(try value("\"script:~/a.sh\"")) == .custom("\"script:~/a.sh\""))
        #expect(SlideDraft(try value("{ up = \"a\", down = \"b\" }")) == .custom("{ up = \"a\", down = \"b\" }"))
    }

    @Test func roundTripsThroughTheParser() throws {
        let drafts: [ActionDraft] = [
            .builtIn(.missionControl), .shortcut("ctrl+left"), .application("Safari"),
            .url("https://example.com/?q=\"x\""), .text("line\nbreak"),
        ]
        for draft in drafts {
            #expect(ActionDraft(try value(draft.tomlText!)) == draft)
        }
    }

    @Test func writesPresetStepsOnlyWhenTheyDiffer() throws {
        #expect(SlideDraft.preset(.volume, step: nil).tomlText == "\"volume\"")
        #expect(SlideDraft.preset(.volume, step: 0.8).tomlText == "\"volume\"")
        let custom = try #require(SlideDraft.preset(.volume, step: 0.55).tomlText)
        #expect(custom == "{ preset = \"volume\", step = 0.55 }")
        #expect(SlideDraft(try value(custom)) == .preset(.volume, step: 0.55))
    }

    @Test func levelPresetsMoveInQuarterSteps() throws {
        let configuration = try ConfigurationParser.parse("[TRACKPAD]\nfour-finger-slide = \"volume\"")
        let binding = configuration.binding(for: .fourFingerSlide, device: .trackpad, application: nil, functionKeyDown: false)
        guard case .slide(let slide) = binding else {
            Issue.record("expected a slide")
            return
        }
        #expect(slide.actions[.up]?.steps == [.builtIn(.volumeUpFine)])
        #expect(slide.detent == 4)
        #expect(configuration.slideTarget(for: slide).step == 0.8)
    }
}
