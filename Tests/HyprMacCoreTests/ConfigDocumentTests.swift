import Testing
@testable import HyprMacCore

struct ConfigDocumentTests {
    @Test func defaultConfigRoundTrips() {
        let doc = ConfigDocument.parse(HyprConfig.defaultText)
        #expect(doc.extraLines.isEmpty)
        #expect(doc.variable("mod") == "ALT")
        let original = HyprConfig.parse(HyprConfig.defaultText)
        let reparsed = HyprConfig.parse(doc.serialize())
        #expect(reparsed.errors.isEmpty)
        #expect(reparsed.binds == original.binds)
        #expect(reparsed.rules.count == original.rules.count)
        #expect(reparsed.gapsIn == original.gapsIn)
        #expect(reparsed.specialScale == original.specialScale)
        // Serializing is stable.
        #expect(ConfigDocument.parse(doc.serialize()).serialize() == doc.serialize())
    }

    @Test func editsAreWritten() {
        var doc = ConfigDocument.parse(HyprConfig.defaultText)
        doc.setVariable("mod", "SUPER")
        doc.gapsIn = 8
        doc.rules.append(.init(action: "workspace 3", classPattern: "^(Zen)$", titlePattern: ""))
        doc.binds.append(.init(mods: "$mod CTRL", key: "x", dispatcher: "exec", argument: "echo #1"))
        doc.execOnce = ["open -a Obsidian"]
        let c = HyprConfig.parse(doc.serialize())
        #expect(c.errors.isEmpty)
        #expect(c.gapsIn == 8)
        #expect(c.binds.last?.modifiers == [.command, .control])
        #expect(c.binds.last?.argument == "echo #1")
        #expect(c.rules.last?.action == .workspace(3))
        #expect(c.execOnce == ["open -a Obsidian"])
    }

    @Test func unknownLinesArePreserved() {
        let doc = ConfigDocument.parse("misc {\n  foo = 1\n}\nbind = ALT, 1, workspace, 1\n")
        #expect(doc.extraLines == ["misc:foo = 1"])
        #expect(doc.binds.count == 1)
    }

    @Test func keyNames() {
        #expect(KeyCodes.name(for: 36) == "return")
        #expect(KeyCodes.name(for: 0) == "a")
        #expect(KeyCodes.name(for: 27) == "minus")
        #expect(KeyCodes.canonicalNames.first == "a")
    }
}
