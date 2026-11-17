import Carbon.HIToolbox
import Foundation
import Testing
@testable import OpenGesturesCore

struct KeystrokeTests {
    @Test func parsesModifiersAndNamedKeys() throws {
        let keystroke = try Keystroke.parse("cmd+shift+F5")
        #expect(keystroke.modifiers == [.command, .shift])
        #expect(keystroke.key == .code(UInt16(kVK_F5)))
    }

    @Test func treatsUppercaseLettersAsShifted() throws {
        #expect(try Keystroke.parse("cmd+Z") == Keystroke(key: .character("z"), modifiers: [.command, .shift]))
    }

    @Test func acceptsPlusAsAKey() throws {
        #expect(try Keystroke.parse("ctrl++") == Keystroke(key: .character("+"), modifiers: [.control]))
        #expect(try Keystroke.parse("cmd+plus") == Keystroke(key: .character("+"), modifiers: [.command]))
    }

    @Test(arguments: ["hyper+a", "cmd+", "cmd+banana", ""])
    func rejectsInvalidKeystrokes(text: String) {
        #expect(throws: BindingError.self) { try Keystroke.parse(text) }
    }

    @Test func parsesActionPrefixes() throws {
        #expect(try BindingParser.parseStep("mouse-4") == .mouseButton(4))
        #expect(try BindingParser.parseStep("middle-click") == .mouseButton(3))
        #expect(try BindingParser.parseStep("app:Safari") == .openApplication("Safari"))
        #expect(try BindingParser.parseStep("things:///add") == .openURL("things:///add"))
        #expect(try BindingParser.parseStep("text:Hello there") == .typeText("Hello there"))
        #expect(throws: BindingError.self) { try BindingParser.parseStep("mouse-40") }
        #expect(throws: BindingError.self) { try BindingParser.parseStep("menu:File") }
    }
}

struct TemplateTests {
    let context = Template.Context(
        clipboard: { " a b&c " },
        now: Date(timeIntervalSince1970: 1_800_000_000),
        timeZone: TimeZone(identifier: "UTC")!
    )

    @Test func expandsPlaceholdersAndFilters() {
        let rendered = Template.render("x://?q={{clipboard|trim|urlencode}}&d={{date}}&t={{time}}", context: context)
        #expect(rendered == "x://?q=a%20b%26c&d=2027-01-15&t=08:00")
    }

    @Test func supportsCustomDateFormats() {
        #expect(Template.render("{{date:yyyyMMdd}}-{{timestamp}}", context: context) == "20270115-1800000000")
    }

    @Test func leavesUnknownPlaceholdersAlone() {
        #expect(Template.render("{{nope}} {{clipboard|shout}} {{open", context: context) == "{{nope}} {{clipboard|shout}} {{open")
    }
}
