import Testing
@testable import BWMenuBar

@Suite("Add Entry")
struct AddEntryTests {

    // MARK: - Generate args

    @Test("builds generate args with defaults")
    func generateArgsDefault() {
        let args = RBWService.generateArgs(length: 16, noSymbols: false, onlyNumbers: false, diceware: false)
        #expect(args == ["rbw", "generate", "16"])
    }

    @Test("builds generate args with no-symbols flag")
    func generateArgsNoSymbols() {
        let args = RBWService.generateArgs(length: 20, noSymbols: true, onlyNumbers: false, diceware: false)
        #expect(args == ["rbw", "generate", "--no-symbols", "20"])
    }

    @Test("builds generate args with only-numbers flag")
    func generateArgsOnlyNumbers() {
        let args = RBWService.generateArgs(length: 12, noSymbols: false, onlyNumbers: true, diceware: false)
        #expect(args == ["rbw", "generate", "--only-numbers", "12"])
    }

    @Test("builds generate args with diceware flag")
    func generateArgsDiceware() {
        let args = RBWService.generateArgs(length: 5, noSymbols: false, onlyNumbers: false, diceware: true)
        #expect(args == ["rbw", "generate", "--diceware", "5"])
    }

    // MARK: - Add entry args

    @Test("builds add args with all fields")
    func addArgsAllFields() {
        let args = RBWService.addEntryArgs(name: "GitHub", user: "carlo", uri: "https://github.com", folder: "dev")
        #expect(args == ["rbw", "add", "--uri", "https://github.com", "--folder", "dev", "GitHub", "carlo"])
    }

    @Test("builds add args with name only")
    func addArgsNameOnly() {
        let args = RBWService.addEntryArgs(name: "WiFi", user: "", uri: "", folder: "")
        #expect(args == ["rbw", "add", "WiFi"])
    }

    @Test("builds add args skipping empty optional fields")
    func addArgsPartial() {
        let args = RBWService.addEntryArgs(name: "AWS", user: "admin", uri: "", folder: "work")
        #expect(args == ["rbw", "add", "--folder", "work", "AWS", "admin"])
    }

    // MARK: - Generate entry args

    @Test("builds generateEntry args with name and user")
    func generateEntryArgs() {
        let args = RBWService.generateEntryArgs(
            name: "GitHub", user: "carlo", length: 20,
            uri: "https://github.com", folder: "dev",
            noSymbols: true, onlyNumbers: false, diceware: false
        )
        #expect(args == ["rbw", "generate", "--no-symbols", "--uri", "https://github.com", "--folder", "dev", "20", "GitHub", "carlo"])
    }

    @Test("builds generateEntry args with name only")
    func generateEntryArgsMinimal() {
        let args = RBWService.generateEntryArgs(
            name: "WiFi", user: "", length: 16,
            uri: "", folder: "",
            noSymbols: false, onlyNumbers: false, diceware: false
        )
        #expect(args == ["rbw", "generate", "16", "WiFi"])
    }

    // MARK: - List folders

    @Test("extracts unique sorted folders from entries")
    @MainActor func listFolders() {
        let entries = [
            VaultEntry(name: "A", user: "", folder: "work"),
            VaultEntry(name: "B", user: "", folder: "dev"),
            VaultEntry(name: "C", user: "", folder: "work"),
            VaultEntry(name: "D", user: "", folder: ""),
        ]
        let service = RBWService()
        service.entries = entries
        let folders = service.listFolders()
        #expect(folders == ["dev", "work"])
    }
}
