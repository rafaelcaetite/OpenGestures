import Testing
@testable import OpenGesturesCore

struct TOMLParserTests {
    @Test func parsesTablesValuesAndComments() throws {
        let document = try TOMLParser.parse("""
            # leading comment
            title = "gestures"   # trailing
            [GENERAL]
            enabled = true
            step = 4.5
            count = 1_000

            [TRACKPAD."Safari, Mail"]
            'literal' = 'C:\\path'
            list = ["a", "b",]
            inline = { up = "x", step = 3 }
            """)

        #expect(document["title"] == .string("gestures"))
        #expect(document.entry("title")?.comment == "trailing")
        guard case .table(let general) = document["GENERAL"] else { Issue.record("GENERAL missing"); return }
        #expect(general["enabled"] == .boolean(true))
        #expect(general["step"] == .float(4.5))
        #expect(general["count"] == .integer(1000))

        guard case .table(let trackpad) = document["TRACKPAD"],
              case .table(let scoped) = trackpad["Safari, Mail"]
        else { Issue.record("scoped table missing"); return }
        #expect(scoped.isInline == false)
        #expect(scoped.line == 8)
        #expect(scoped["literal"] == .string("C:\\path"))
        #expect(scoped["list"] == .array([.string("a"), .string("b")]))
        guard case .table(let inline) = scoped["inline"] else { Issue.record("inline missing"); return }
        #expect(inline.isInline)
        #expect(inline.keys == ["up", "step"])
    }

    @Test func decodesEscapes() throws {
        let document = try TOMLParser.parse(#"text = "a\"b\\c\u00e9\n""#)
        #expect(document["text"] == .string("a\"b\\cé\n"))
    }

    @Test func reportsDuplicateKeysWithTheirLine() {
        #expect(throws: TOMLError(line: 3, message: "key \"a\" is defined more than once")) {
            try TOMLParser.parse("a = 1\n\na = 2")
        }
    }

    @Test(arguments: [
        ("a = \"open", "unterminated string"),
        ("[[items]]", "arrays of tables ([[...]]) are not supported"),
        ("a = 1979-05-27", "dates and times are not supported"),
        ("a = 1 2", "unexpected \"2\" after value"),
        ("[a]\n[a]", "table [a] is defined more than once"),
    ])
    func rejectsUnsupportedInput(source: String, message: String) {
        #expect(throws: TOMLError.self) { try TOMLParser.parse(source) }
        do {
            _ = try TOMLParser.parse(source)
        } catch {
            #expect(error.message == message)
        }
    }
}

extension TOMLParserTests {
    @Test func acceptsPlusInBareKeys() throws {
        let document = try TOMLParser.parse("fn+four-finger-tap = 1\n\"fn+quoted\" = 2")
        #expect(document.keys == ["fn+four-finger-tap", "fn+quoted"])
    }
}
