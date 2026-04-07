// Tests/BWMenuBarTests/ParsingTests.swift
import Testing
@testable import BWMenuBar

@Suite("VaultEntry Parsing")
struct ParsingTests {
    @Test("parses tab-separated rbw list output")
    func parseFullOutput() {
        let output = """
        GitHub\tcarlopizzuto\tdev
        AWS Console\tadmin@company.com\twork
        Netflix\tuser@example.com\t
        """
        let entries = VaultEntry.parse(rbwOutput: output)

        #expect(entries.count == 3)
        #expect(entries[0].name == "GitHub")
        #expect(entries[0].user == "carlopizzuto")
        #expect(entries[0].folder == "dev")
        #expect(entries[2].folder == "")
    }

    @Test("skips blank lines")
    func skipBlanks() {
        let output = """
        GitHub\tuser\tfolder

        Netflix\tuser2\t
        """
        let entries = VaultEntry.parse(rbwOutput: output)
        #expect(entries.count == 2)
    }

    @Test("handles entries with name only")
    func nameOnly() {
        let output = "WiFi Password\t\t\n"
        let entries = VaultEntry.parse(rbwOutput: output)
        #expect(entries.count == 1)
        #expect(entries[0].name == "WiFi Password")
        #expect(entries[0].user == "")
    }

    @Test("filters entries by search query")
    func filtering() {
        let entries = [
            VaultEntry(name: "GitHub", user: "carlo", folder: ""),
            VaultEntry(name: "Gmail", user: "carlo@gmail.com", folder: ""),
            VaultEntry(name: "AWS", user: "admin", folder: ""),
        ]
        let filtered = entries.filter { $0.matches(query: "git") }
        #expect(filtered.count == 1)
        #expect(filtered[0].name == "GitHub")
    }

    @Test("filter matches username too")
    func filterByUser() {
        let entries = [
            VaultEntry(name: "Site A", user: "carlo", folder: ""),
            VaultEntry(name: "Site B", user: "admin", folder: ""),
        ]
        let filtered = entries.filter { $0.matches(query: "carlo") }
        #expect(filtered.count == 1)
    }

    @Test("empty query matches everything")
    func emptyQuery() {
        let entries = [
            VaultEntry(name: "GitHub", user: "carlo", folder: ""),
        ]
        let filtered = entries.filter { $0.matches(query: "") }
        #expect(filtered.count == 1)
    }
}
