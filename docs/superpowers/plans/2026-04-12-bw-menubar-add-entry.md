# BWMenuBar Add Entry — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "new login" creation form to the BWMenuBar macOS menubar app, supporting both manual password entry and password generation via `rbw add` and `rbw generate`.

**Architecture:** Single new view (`AddEntryView`) with progressive disclosure for generate options. Navigation is a boolean state swap in `VaultListView` (list ↔ form). `RBWService` gains four new methods and a `shell()` enhancement for stdin piping. Password is piped to `rbw add` via stdin (no EDITOR trick needed).

**Tech Stack:** SwiftUI (macOS 14+), Swift Testing, `rbw` CLI

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/BWMenuBar/RBWService.swift` | Modify | Add `shell()` stdin support, `addEntry()`, `generateEntry()`, `generatePassword()`, `listFolders()` |
| `Sources/BWMenuBar/AddEntryView.swift` | Create | Form view: fields, generate toggle, DisclosureGroup, save/back actions |
| `Sources/BWMenuBar/VaultListView.swift` | Modify | Add + button, `showingAddEntry` state, view switching, confirmation flash |
| `Tests/BWMenuBarTests/AddEntryTests.swift` | Create | Tests for generate arg building, folder extraction, addEntry arg building |

---

### Task 1: Enhance shell() with stdin support

**Files:**
- Modify: `bw-menubar/Sources/BWMenuBar/RBWService.swift:20-49`

- [ ] **Step 1: Add stdinData parameter to shell()**

Change the existing `shell()` signature and implementation to accept optional stdin data. In `bw-menubar/Sources/BWMenuBar/RBWService.swift`, replace the current `shell()` method (lines 20-49):

```swift
private func shell(_ args: [String], stdinData: Data? = nil) async -> (output: String, exitCode: Int32) {
    await Task.detached {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = stdout
        process.standardError = Pipe()

        // LaunchAgent/app bundles get a minimal PATH — include Homebrew
        var env = ProcessInfo.processInfo.environment
        let brewPaths = "/opt/homebrew/bin:/opt/homebrew/sbin"
        env["PATH"] = brewPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        process.environment = env

        // Pipe stdin data if provided
        if let stdinData {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            stdinPipe.fileHandleForWriting.write(stdinData)
            stdinPipe.fileHandleForWriting.closeFile()
        }

        do {
            try process.run()
        } catch {
            return ("", Int32(-1))
        }

        // Read before waitUntilExit to avoid pipe buffer deadlock
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (output, process.terminationStatus)
    }.value
}
```

- [ ] **Step 2: Verify existing tests still pass**

Run: `cd /Users/carlopizzuto/.dotfiles/bw-menubar && swift test 2>&1`
Expected: All 6 ParsingTests pass. The default `stdinData: nil` preserves all existing call sites.

- [ ] **Step 3: Verify app builds**

Run: `cd /Users/carlopizzuto/.dotfiles/bw-menubar && swift build 2>&1`
Expected: Build succeeds with no warnings.

- [ ] **Step 4: Commit**

```bash
git add bw-menubar/Sources/BWMenuBar/RBWService.swift
git commit -m "feat(bw-menubar): add stdin piping support to shell() helper"
```

---

### Task 2: Add RBWService methods (TDD)

**Files:**
- Create: `bw-menubar/Tests/BWMenuBarTests/AddEntryTests.swift`
- Modify: `bw-menubar/Sources/BWMenuBar/RBWService.swift`

- [ ] **Step 1: Write tests for generatePassword arg building and listFolders**

Create `bw-menubar/Tests/BWMenuBarTests/AddEntryTests.swift`:

```swift
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
    func listFolders() {
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
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `cd /Users/carlopizzuto/.dotfiles/bw-menubar && swift test 2>&1`
Expected: Compilation fails — `RBWService.generateArgs`, `RBWService.addEntryArgs`, `RBWService.generateEntryArgs`, `RBWService.listFolders()` don't exist yet.

- [ ] **Step 3: Implement static arg-building helpers and listFolders**

Add to `bw-menubar/Sources/BWMenuBar/RBWService.swift`, inside the `RBWService` class, after the existing `startup()` method and before the closing `}`:

```swift
// MARK: - Add entry operations

/// Build args for `rbw generate <length>` (preview only, no save).
static func generateArgs(length: Int, noSymbols: Bool, onlyNumbers: Bool, diceware: Bool) -> [String] {
    var args = ["rbw", "generate"]
    if noSymbols { args.append("--no-symbols") }
    if onlyNumbers { args.append("--only-numbers") }
    if diceware { args.append("--diceware") }
    args.append("\(length)")
    return args
}

/// Build args for `rbw add <name> [user]` with optional flags.
static func addEntryArgs(name: String, user: String, uri: String, folder: String) -> [String] {
    var args = ["rbw", "add"]
    if !uri.isEmpty { args += ["--uri", uri] }
    if !folder.isEmpty { args += ["--folder", folder] }
    args.append(name)
    if !user.isEmpty { args.append(user) }
    return args
}

/// Build args for `rbw generate <length> <name> [user]` with optional flags (saves entry).
static func generateEntryArgs(
    name: String, user: String, length: Int,
    uri: String, folder: String,
    noSymbols: Bool, onlyNumbers: Bool, diceware: Bool
) -> [String] {
    var args = ["rbw", "generate"]
    if noSymbols { args.append("--no-symbols") }
    if onlyNumbers { args.append("--only-numbers") }
    if diceware { args.append("--diceware") }
    if !uri.isEmpty { args += ["--uri", uri] }
    if !folder.isEmpty { args += ["--folder", folder] }
    args.append("\(length)")
    args.append(name)
    if !user.isEmpty { args.append(user) }
    return args
}

/// Generate a password without saving (for form preview).
func generatePassword(length: Int, noSymbols: Bool, onlyNumbers: Bool, diceware: Bool) async -> String? {
    let args = Self.generateArgs(length: length, noSymbols: noSymbols, onlyNumbers: onlyNumbers, diceware: diceware)
    let (output, code) = await shell(args)
    return code == 0 && !output.isEmpty ? output : nil
}

/// Add a login entry with a manual password piped via stdin.
func addEntry(name: String, user: String, password: String, uri: String, folder: String) async -> Bool {
    let args = Self.addEntryArgs(name: name, user: user, uri: uri, folder: folder)
    let stdinData = password.data(using: .utf8)
    let (_, code) = await shell(args, stdinData: stdinData)
    return code == 0
}

/// Add a login entry with a generated password.
func generateEntry(
    name: String, user: String, length: Int,
    uri: String, folder: String,
    noSymbols: Bool, onlyNumbers: Bool, diceware: Bool
) async -> Bool {
    let args = Self.generateEntryArgs(
        name: name, user: user, length: length,
        uri: uri, folder: folder,
        noSymbols: noSymbols, onlyNumbers: onlyNumbers, diceware: diceware
    )
    let (_, code) = await shell(args)
    return code == 0
}

/// Extract unique folder names from loaded entries for autocomplete.
func listFolders() -> [String] {
    Array(Set(entries.map(\.folder).filter { !$0.isEmpty })).sorted()
}
```

- [ ] **Step 4: Run tests — verify they all pass**

Run: `cd /Users/carlopizzuto/.dotfiles/bw-menubar && swift test 2>&1`
Expected: All 17 tests pass (6 ParsingTests + 11 AddEntryTests).

- [ ] **Step 5: Commit**

```bash
git add bw-menubar/Sources/BWMenuBar/RBWService.swift bw-menubar/Tests/BWMenuBarTests/AddEntryTests.swift
git commit -m "feat(bw-menubar): add entry creation and password generation methods to RBWService"
```

---

### Task 3: Create AddEntryView

**Files:**
- Create: `bw-menubar/Sources/BWMenuBar/AddEntryView.swift`

- [ ] **Step 1: Create the AddEntryView with all form fields and generate toggle**

Create `bw-menubar/Sources/BWMenuBar/AddEntryView.swift`:

```swift
// Sources/BWMenuBar/AddEntryView.swift
import SwiftUI

struct AddEntryView: View {
    let service: RBWService
    @Binding var isPresented: Bool
    var onSaved: () -> Void

    @State private var name = ""
    @State private var user = ""
    @State private var password = ""
    @State private var uri = ""
    @State private var folder = ""

    @State private var generateMode = false
    @State private var generatedPassword = ""
    @State private var genLength: Double = 16
    @State private var noSymbols = false
    @State private var onlyNumbers = false
    @State private var diceware = false

    @State private var isSaving = false
    @State private var errorMessage: String?

    private var lengthRange: ClosedRange<Double> {
        diceware ? 3...10 : 8...64
    }

    private var lengthDefault: Double {
        diceware ? 5 : 16
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    formFields
                    passwordSection
                    generateToggle
                    if generateMode {
                        generateOptions
                    }
                    optionalFields
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                    saveButton
                }
                .padding(12)
            }
        }
        .frame(width: 360)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                isPresented = false
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            Spacer()

            Text("New Login")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            // Balance the back button width
            Color.clear.frame(width: 50, height: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Form fields

    private var formFields: some View {
        VStack(spacing: 10) {
            LabeledField("NAME *") {
                TextField("Entry name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledField("USERNAME") {
                TextField("email or username", text: $user)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Password section

    private var passwordSection: some View {
        LabeledField(generateMode ? "PASSWORD" : "PASSWORD") {
            HStack(spacing: 6) {
                SecureField("password", text: $password)
                    .textFieldStyle(.roundedBorder)
                if !password.isEmpty {
                    Button {
                        Clipboard.copyAndClear(password)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy password")
                }
            }
        }
    }

    // MARK: - Generate toggle

    private var generateToggle: some View {
        HStack {
            Toggle("Generate Password", isOn: $generateMode)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            if generateMode {
                Button {
                    Task { await regenerate() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                        Text("Regenerate")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: generateMode) { _, newValue in
            if newValue {
                Task { await regenerate() }
            }
        }
    }

    // MARK: - Generate options

    private var generateOptions: some View {
        VStack(spacing: 8) {
            // Length slider
            HStack {
                Text(diceware ? "WORDS" : "LENGTH")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Slider(value: $genLength, in: lengthRange, step: 1)
                    .frame(width: 140)
                Text("\(Int(genLength))")
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 24, alignment: .trailing)
            }

            // Option pills
            HStack(spacing: 6) {
                OptionPill("No symbols", isOn: $noSymbols)
                    .disabled(diceware)
                OptionPill("Numbers only", isOn: $onlyNumbers)
                    .disabled(diceware)
                OptionPill("Diceware", isOn: $diceware)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onChange(of: genLength) { _, _ in
            Task { await regenerate() }
        }
        .onChange(of: noSymbols) { _, _ in
            Task { await regenerate() }
        }
        .onChange(of: onlyNumbers) { _, _ in
            Task { await regenerate() }
        }
        .onChange(of: diceware) { _, newValue in
            if newValue {
                noSymbols = false
                onlyNumbers = false
                genLength = 5
            } else {
                genLength = 16
            }
            Task { await regenerate() }
        }
    }

    // MARK: - Optional fields

    private var optionalFields: some View {
        VStack(spacing: 10) {
            LabeledField("URI") {
                TextField("https://example.com", text: $uri)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledField("FOLDER") {
                TextField("optional", text: $folder)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Save button

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            } else {
                Text("Save Entry")
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
    }

    // MARK: - Actions

    private func regenerate() async {
        guard let pw = await service.generatePassword(
            length: Int(genLength),
            noSymbols: noSymbols,
            onlyNumbers: onlyNumbers,
            diceware: diceware
        ) else { return }
        password = pw
        generatedPassword = pw
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let success: Bool

        if generateMode && password == generatedPassword && !generatedPassword.isEmpty {
            // User didn't edit the generated password — use rbw generate to save
            success = await service.generateEntry(
                name: trimmedName, user: user, length: Int(genLength),
                uri: uri, folder: folder,
                noSymbols: noSymbols, onlyNumbers: onlyNumbers, diceware: diceware
            )
        } else {
            // Manual password or user edited the generated one — use rbw add
            success = await service.addEntry(
                name: trimmedName, user: user, password: password,
                uri: uri, folder: folder
            )
        }

        isSaving = false

        if success {
            onSaved()
        } else {
            errorMessage = "Failed to save entry. Check if an entry with this name already exists."
        }
    }
}

// MARK: - Reusable components

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct OptionPill: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(title)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isOn ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15))
                .foregroundStyle(isOn ? .primary : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd /Users/carlopizzuto/.dotfiles/bw-menubar && swift build 2>&1`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add bw-menubar/Sources/BWMenuBar/AddEntryView.swift
git commit -m "feat(bw-menubar): create AddEntryView with form fields and generate toggle"
```

---

### Task 4: Wire AddEntryView into VaultListView

**Files:**
- Modify: `bw-menubar/Sources/BWMenuBar/VaultListView.swift`

- [ ] **Step 1: Add state and + button to VaultListView**

In `bw-menubar/Sources/BWMenuBar/VaultListView.swift`, add two new state properties after the existing `@State private var searchText = ""` (line 8):

```swift
@State private var showingAddEntry = false
@State private var confirmationMessage: String?
```

- [ ] **Step 2: Add conditional view switching in body**

Replace the current `body` (lines 13-30) with:

```swift
var body: some View {
    VStack(spacing: 0) {
        if showingAddEntry {
            AddEntryView(service: service, isPresented: $showingAddEntry) {
                Task {
                    await service.loadEntries()
                    confirmationMessage = "Entry added"
                    try? await Task.sleep(for: .seconds(2))
                    confirmationMessage = nil
                }
            }
        } else {
            switch service.state {
            case .loading:
                loadingView
            case .locked:
                lockedView
            case .error(let message):
                errorView(message)
            case .ready:
                readyView
            }
        }
    }
    .frame(width: 360)
    .task {
        await service.startup()
    }
}
```

- [ ] **Step 3: Add + button and confirmation flash to the footer**

Replace the existing footer `HStack` (lines 133-151 in the original) with:

```swift
HStack {
    if let confirmationMessage {
        Text(confirmationMessage)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.green)
    } else {
        Text("\(filtered.count) entries")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
    }
    Spacer()
    Button {
        showingAddEntry = true
    } label: {
        Image(systemName: "plus")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }
    .buttonStyle(.plain)
    .help("Add entry")
    Button {
        Task {
            await service.sync()
            await service.loadEntries()
        }
    } label: {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
    }
    .buttonStyle(.plain)
    .help("Sync vault")
}
.padding(.horizontal, 10)
.padding(.vertical, 6)
```

- [ ] **Step 4: Verify it compiles and all tests pass**

Run: `cd /Users/carlopizzuto/.dotfiles/bw-menubar && swift build 2>&1 && swift test 2>&1`
Expected: Build succeeds, all 17 tests pass.

- [ ] **Step 5: Manual test**

Run: `cd /Users/carlopizzuto/.dotfiles/bw-menubar && make run`

Verify:
1. The + button appears in the footer next to the sync button
2. Clicking + shows the AddEntryView form
3. "← Back" returns to the vault list
4. Fill in Name + Password, click "Save Entry" → returns to list, "Entry added" flashes green
5. Toggle "Generate Password" on → password field populates, options expand
6. Adjust length slider, toggle options → password regenerates
7. Click "Regenerate" → new password appears
8. Save with generated password → entry appears in list
9. Clean up test entries: `rbw remove "test-entry-name" "user"`

- [ ] **Step 6: Commit**

```bash
git add bw-menubar/Sources/BWMenuBar/VaultListView.swift
git commit -m "feat(bw-menubar): wire AddEntryView with + button, navigation, and confirmation flash"
```

---

### Task 5: Rebuild and reinstall

**Files:**
- No code changes — build and deploy only

- [ ] **Step 1: Rebuild and reinstall the app**

Run: `cd /Users/carlopizzuto/.dotfiles/bw-menubar && make install 2>&1`
Expected: Build succeeds, app installed to ~/Applications/BWMenuBar.app

- [ ] **Step 2: Reload the LaunchAgent**

Run:
```bash
launchctl unload ~/Library/LaunchAgents/com.carlopizzuto.bw-menubar.plist 2>/dev/null
launchctl load ~/Library/LaunchAgents/com.carlopizzuto.bw-menubar.plist
```

- [ ] **Step 3: Verify the installed app works**

Click the key icon in the menubar. Verify:
1. Vault list loads (rbw found via Homebrew PATH)
2. The + button is visible in the footer
3. Creating an entry via the form works end-to-end
4. Clean up any test entries afterward

- [ ] **Step 4: Commit (no code changes — skip if nothing to commit)**

Only commit if the Makefile or other build config needed changes during this step.
