# Entry Detail & Edit View — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace click-to-copy-password with a full entry detail view showing all fields, click-to-copy with animated feedback, hover-to-reveal password, and inline editing for password and notes.

**Architecture:** New `EntryDetailView` replaces the vault list via the same view-swap pattern used by `AddEntryView`. A new `EntryDetail` struct models the full JSON from `rbw get --raw`. The `RBWService` gains methods for fetching detail, TOTP codes, and editing entries. The `VaultListView` adds a quick-copy icon per row and routes clicks to the detail view.

**Tech Stack:** SwiftUI (macOS 14+), Swift Testing, rbw CLI

**Spec:** `docs/superpowers/specs/2026-04-12-bw-menubar-entry-detail-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `Sources/BWMenuBar/EntryDetail.swift` | **New** — `EntryDetail` struct + JSON parsing from `rbw get --raw` |
| `Sources/BWMenuBar/EntryDetailView.swift` | **New** — Detail view with grouped cards, click-to-copy, hover-reveal, inline editing, TOTP timer |
| `Sources/BWMenuBar/CopyableField.swift` | **New** — Reusable click-to-copy SwiftUI component with "Copied" flash animation |
| `Sources/BWMenuBar/RBWService.swift` | **Modify** — Add `shell()` `extraEnv` param, `getEntryDetail()`, `getTOTPCode()`, `editEntry()`, `editEntryArgs()` |
| `Sources/BWMenuBar/VaultListView.swift` | **Modify** — Add `selectedEntry` state, quick-copy icon on rows, route to detail view |
| `Tests/BWMenuBarTests/EntryDetailTests.swift` | **New** — Tests for JSON parsing, edit arg building |

---

### Task 1: EntryDetail Model + JSON Parsing

**Files:**
- Create: `Sources/BWMenuBar/EntryDetail.swift`
- Create: `Tests/BWMenuBarTests/EntryDetailTests.swift`

- [ ] **Step 1: Write failing tests for EntryDetail JSON parsing**

Create `Tests/BWMenuBarTests/EntryDetailTests.swift`:

```swift
import Testing
@testable import BWMenuBar

@Suite("Entry Detail")
struct EntryDetailTests {

    // MARK: - JSON parsing

    @Test("parses full JSON with all fields")
    func parseFullJSON() {
        let json = """
        {
          "id": "abc-123",
          "folder": "dev",
          "name": "GitHub",
          "data": {
            "username": "carlo@example.com",
            "password": "s3cret!",
            "totp": "otpauth://totp/GitHub?secret=ABC",
            "uris": [
              {"uri": "https://github.com", "match_type": null},
              {"uri": "https://github.com/login", "match_type": null}
            ]
          },
          "fields": [
            {"name": "recovery", "value": "code-123"}
          ],
          "notes": "Personal account",
          "history": [
            {"last_used_date": "2026-01-01T00:00:00Z", "password": "oldpass"}
          ]
        }
        """
        let detail = EntryDetail.parse(json: json)
        #expect(detail != nil)
        #expect(detail!.id == "abc-123")
        #expect(detail!.name == "GitHub")
        #expect(detail!.username == "carlo@example.com")
        #expect(detail!.password == "s3cret!")
        #expect(detail!.hasTotp == true)
        #expect(detail!.uris == ["https://github.com", "https://github.com/login"])
        #expect(detail!.folder == "dev")
        #expect(detail!.notes == "Personal account")
        #expect(detail!.fields.count == 1)
        #expect(detail!.fields[0].name == "recovery")
        #expect(detail!.fields[0].value == "code-123")
        #expect(detail!.history.count == 1)
        #expect(detail!.history[0].password == "oldpass")
    }

    @Test("parses minimal JSON with nulls and empty arrays")
    func parseMinimalJSON() {
        let json = """
        {
          "id": "def-456",
          "folder": null,
          "name": "WiFi",
          "data": {
            "username": "",
            "password": "wifipass",
            "totp": null,
            "uris": []
          },
          "fields": [],
          "notes": null,
          "history": []
        }
        """
        let detail = EntryDetail.parse(json: json)
        #expect(detail != nil)
        #expect(detail!.id == "def-456")
        #expect(detail!.name == "WiFi")
        #expect(detail!.username == "")
        #expect(detail!.password == "wifipass")
        #expect(detail!.hasTotp == false)
        #expect(detail!.uris.isEmpty)
        #expect(detail!.folder == nil)
        #expect(detail!.notes == nil)
        #expect(detail!.fields.isEmpty)
        #expect(detail!.history.isEmpty)
    }

    @Test("returns nil for invalid JSON")
    func parseInvalidJSON() {
        let detail = EntryDetail.parse(json: "not json")
        #expect(detail == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/carlopizzuto/.dotfiles/bw-menubar && swift test --filter EntryDetailTests 2>&1`
Expected: FAIL — `EntryDetail` type does not exist.

- [ ] **Step 3: Implement EntryDetail struct**

Create `Sources/BWMenuBar/EntryDetail.swift`:

```swift
// Sources/BWMenuBar/EntryDetail.swift
import Foundation

struct EntryDetail {
    let id: String
    let name: String
    let username: String
    let password: String
    let hasTotp: Bool
    let uris: [String]
    let folder: String?
    let notes: String?
    let fields: [(name: String, value: String)]
    let history: [(password: String, lastUsedDate: String)]

    /// Parse the JSON output of `rbw get --raw`.
    static func parse(json: String) -> EntryDetail? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] as? String,
              let name = obj["name"] as? String,
              let entryData = obj["data"] as? [String: Any]
        else { return nil }

        let username = entryData["username"] as? String ?? ""
        let password = entryData["password"] as? String ?? ""
        let hasTotp = (entryData["totp"] as? String) != nil
        let rawURIs = entryData["uris"] as? [[String: Any]] ?? []
        let uris = rawURIs.compactMap { $0["uri"] as? String }
        let folder = obj["folder"] as? String
        let notes = obj["notes"] as? String

        let rawFields = obj["fields"] as? [[String: Any]] ?? []
        let fields = rawFields.compactMap { dict -> (name: String, value: String)? in
            guard let name = dict["name"] as? String,
                  let value = dict["value"] as? String else { return nil }
            return (name: name, value: value)
        }

        let rawHistory = obj["history"] as? [[String: Any]] ?? []
        let history = rawHistory.compactMap { dict -> (password: String, lastUsedDate: String)? in
            guard let pw = dict["password"] as? String,
                  let date = dict["last_used_date"] as? String else { return nil }
            return (password: pw, lastUsedDate: date)
        }

        return EntryDetail(
            id: id, name: name, username: username, password: password,
            hasTotp: hasTotp, uris: uris, folder: folder, notes: notes,
            fields: fields, history: history
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/carlopizzuto/.dotfiles/bw-menubar && swift test --filter EntryDetailTests 2>&1`
Expected: All 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/BWMenuBar/EntryDetail.swift Tests/BWMenuBarTests/EntryDetailTests.swift
git commit -m "feat(bw-menubar): add EntryDetail model with JSON parsing"
```

---

### Task 2: RBWService — getEntryDetail, getTOTPCode, editEntry

**Files:**
- Modify: `Sources/BWMenuBar/RBWService.swift:23` (shell method), append new methods after line 219
- Modify: `Tests/BWMenuBarTests/EntryDetailTests.swift`

- [ ] **Step 1: Write failing tests for arg builders and edit mechanism**

Append to `Tests/BWMenuBarTests/EntryDetailTests.swift`:

```swift
    // MARK: - Edit entry args

    @Test("builds edit args with all fields")
    func editArgsAllFields() {
        let entry = VaultEntry(name: "GitHub", user: "carlo", folder: "dev")
        let args = RBWService.editEntryArgs(for: entry)
        #expect(args == ["rbw", "edit", "--folder", "dev", "GitHub", "carlo"])
    }

    @Test("builds edit args with name only")
    func editArgsNameOnly() {
        let entry = VaultEntry(name: "WiFi", user: "", folder: "")
        let args = RBWService.editEntryArgs(for: entry)
        #expect(args == ["rbw", "edit", "WiFi"])
    }

    @Test("builds edit stdin with password and notes")
    func editStdinWithNotes() {
        let stdin = RBWService.editStdin(password: "newpass", notes: "line1\nline2")
        #expect(stdin == "newpass\nline1\nline2")
    }

    @Test("builds edit stdin with password only")
    func editStdinNoNotes() {
        let stdin = RBWService.editStdin(password: "newpass", notes: nil)
        #expect(stdin == "newpass")
    }

    @Test("builds edit stdin with password and empty notes")
    func editStdinEmptyNotes() {
        let stdin = RBWService.editStdin(password: "newpass", notes: "")
        #expect(stdin == "newpass")
    }

    // MARK: - Detail entry args

    @Test("builds getEntryDetail args with folder and user")
    func detailArgsAllFields() {
        let entry = VaultEntry(name: "GitHub", user: "carlo", folder: "dev")
        let args = RBWService.getEntryDetailArgs(for: entry)
        #expect(args == ["rbw", "get", "--raw", "--folder", "dev", "GitHub", "carlo"])
    }

    @Test("builds getEntryDetail args with name only")
    func detailArgsNameOnly() {
        let entry = VaultEntry(name: "WiFi", user: "", folder: "")
        let args = RBWService.getEntryDetailArgs(for: entry)
        #expect(args == ["rbw", "get", "--raw", "WiFi"])
    }

    // MARK: - TOTP args

    @Test("builds getTOTPCode args with folder and user")
    func totpArgsAllFields() {
        let entry = VaultEntry(name: "GitHub", user: "carlo", folder: "dev")
        let args = RBWService.getTOTPCodeArgs(for: entry)
        #expect(args == ["rbw", "code", "--folder", "dev", "GitHub", "carlo"])
    }

    @Test("builds getTOTPCode args with name only")
    func totpArgsNameOnly() {
        let entry = VaultEntry(name: "WiFi", user: "", folder: "")
        let args = RBWService.getTOTPCodeArgs(for: entry)
        #expect(args == ["rbw", "code", "WiFi"])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/carlopizzuto/.dotfiles/bw-menubar && swift test --filter EntryDetailTests 2>&1`
Expected: FAIL — `editEntryArgs`, `editStdin`, `getEntryDetailArgs`, `getTOTPCodeArgs` do not exist.

- [ ] **Step 3: Add extraEnv parameter to shell()**

In `RBWService.swift`, modify the `shell` method signature at line 23 to add `extraEnv`:

Change:
```swift
private func shell(_ args: [String], stdinData: Data? = nil) async -> (output: String, exitCode: Int32) {
```
To:
```swift
private func shell(_ args: [String], stdinData: Data? = nil, extraEnv: [String: String]? = nil) async -> (output: String, exitCode: Int32) {
```

After the line `env["PATH"] = brewPaths + ":" + (env["PATH"] ?? ...)` (line 35), add:

```swift
            if let extraEnv {
                for (key, value) in extraEnv { env[key] = value }
            }
```

- [ ] **Step 4: Add static arg builder methods and instance methods**

Append to `RBWService.swift` before the closing `}` of the class (before line 220):

```swift
    // MARK: - Entry detail operations

    /// Build args for `rbw get --raw [--folder FOLDER] NAME [USER]`.
    nonisolated static func getEntryDetailArgs(for entry: VaultEntry) -> [String] {
        var args = ["rbw", "get", "--raw"]
        if !entry.folder.isEmpty { args += ["--folder", entry.folder] }
        args.append(entry.name)
        if !entry.user.isEmpty { args.append(entry.user) }
        return args
    }

    /// Build args for `rbw code [--folder FOLDER] NAME [USER]`.
    nonisolated static func getTOTPCodeArgs(for entry: VaultEntry) -> [String] {
        var args = ["rbw", "code"]
        if !entry.folder.isEmpty { args += ["--folder", entry.folder] }
        args.append(entry.name)
        if !entry.user.isEmpty { args.append(entry.user) }
        return args
    }

    /// Build args for `rbw edit [--folder FOLDER] NAME [USER]`.
    nonisolated static func editEntryArgs(for entry: VaultEntry) -> [String] {
        var args = ["rbw", "edit"]
        if !entry.folder.isEmpty { args += ["--folder", entry.folder] }
        args.append(entry.name)
        if !entry.user.isEmpty { args.append(entry.user) }
        return args
    }

    /// Build the stdin payload for `rbw edit`: line 1 = password, rest = notes.
    nonisolated static func editStdin(password: String, notes: String?) -> String {
        guard let notes, !notes.isEmpty else { return password }
        return password + "\n" + notes
    }

    /// Fetch full entry detail as JSON.
    func getEntryDetail(for entry: VaultEntry) async -> EntryDetail? {
        let args = Self.getEntryDetailArgs(for: entry)
        let (output, code) = await shell(args)
        guard code == 0 else { return nil }
        return EntryDetail.parse(json: output)
    }

    /// Fetch current TOTP code.
    func getTOTPCode(for entry: VaultEntry) async -> String? {
        let args = Self.getTOTPCodeArgs(for: entry)
        let (output, code) = await shell(args)
        return code == 0 && !output.isEmpty ? output : nil
    }

    /// Edit an entry's password and/or notes via EDITOR=cat trick.
    func editEntry(for entry: VaultEntry, password: String, notes: String?) async -> Bool {
        let args = Self.editEntryArgs(for: entry)
        let stdin = Self.editStdin(password: password, notes: notes)
        let stdinData = stdin.data(using: .utf8)
        let (_, code) = await shell(args, stdinData: stdinData, extraEnv: ["EDITOR": "cat"])
        return code == 0
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/carlopizzuto/.dotfiles/bw-menubar && swift test --filter EntryDetailTests 2>&1`
Expected: All tests PASS (3 existing + 10 new = 13 total).

- [ ] **Step 6: Run full test suite to check for regressions**

Run: `cd /Users/carlopizzuto/.dotfiles/bw-menubar && swift test 2>&1`
Expected: All tests PASS (including AddEntryTests).

- [ ] **Step 7: Commit**

```bash
git add Sources/BWMenuBar/RBWService.swift Tests/BWMenuBarTests/EntryDetailTests.swift
git commit -m "feat(bw-menubar): add getEntryDetail, getTOTPCode, editEntry to RBWService"
```

---

### Task 3: CopyableField Reusable Component

**Files:**
- Create: `Sources/BWMenuBar/CopyableField.swift`

This is the click-to-copy component with the "Copied" cross-fade animation. It will be used by both `EntryDetailView` and the quick-copy flash in `VaultListView`.

- [ ] **Step 1: Create CopyableField component**

Create `Sources/BWMenuBar/CopyableField.swift`:

```swift
// Sources/BWMenuBar/CopyableField.swift
import SwiftUI

/// A view that copies text to the clipboard on click, showing a brief "Copied" flash.
struct CopyableField<Content: View>: View {
    let text: String
    @ViewBuilder let content: Content
    @State private var showCopied = false

    var body: some View {
        Button {
            guard !showCopied else { return }
            Clipboard.copyAndClear(text)
            showCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopied = false
            }
        } label: {
            ZStack {
                content
                    .opacity(showCopied ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: showCopied)

                Text("Copied")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .opacity(showCopied ? 1 : 0)
                    .offset(y: showCopied ? 0 : 4)
                    .animation(.easeInOut(duration: 0.2), value: showCopied)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.primary.opacity(0.001)) // Always hit-testable
        )
        .onHover { hovering in
            // Handled by the parent for hover effects if needed
        }
    }
}

/// A variant for the notes copy-all button that overlays "Copied" on an external content area.
/// The `isCopied` binding is controlled by the parent so the overlay can cover the notes text.
struct CopyAllButton: View {
    let text: String
    @Binding var isCopied: Bool

    var body: some View {
        Button {
            guard !isCopied else { return }
            Clipboard.copyAndClear(text)
            isCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isCopied = false
            }
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Copy all")
    }
}
```

- [ ] **Step 2: Verify build compiles**

Run: `cd /Users/carlopizzuto/.dotfiles/bw-menubar && swift build 2>&1`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/BWMenuBar/CopyableField.swift
git commit -m "feat(bw-menubar): add CopyableField reusable click-to-copy component"
```

---

### Task 4: EntryDetailView — Main View

**Files:**
- Create: `Sources/BWMenuBar/EntryDetailView.swift`

This is the main detail view with grouped cards, all fields, click-to-copy, hover-reveal password, TOTP timer, and inline editing.

- [ ] **Step 1: Create EntryDetailView**

Create `Sources/BWMenuBar/EntryDetailView.swift`:

```swift
// Sources/BWMenuBar/EntryDetailView.swift
import SwiftUI

struct EntryDetailView: View {
    let entry: VaultEntry
    let service: RBWService
    @Binding var isPresented: Bool

    @State private var detail: EntryDetail?
    @State private var totpCode: String?
    @State private var totpSecondsRemaining: Int = 0
    @State private var isLoading = true
    @State private var errorMessage: String?

    // Editing state
    @State private var editingPassword = false
    @State private var editingNotes = false
    @State private var editPasswordText = ""
    @State private var editNotesText = ""
    @State private var editError: String?
    @State private var isSaving = false

    // Notes copy-all overlay
    @State private var notesCopied = false

    // TOTP refresh timer
    @State private var totpTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isLoading {
                loadingView
            } else if let errorMessage {
                errorView(errorMessage)
            } else if let detail {
                ScrollView {
                    VStack(spacing: 10) {
                        credentialsCard(detail)
                        detailsCard(detail)
                        notesCard(detail)
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 360)
        .task { await loadDetail() }
        .onDisappear { totpTimer?.invalidate() }
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

            Text(entry.name)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)

            Spacer()

            Color.clear.frame(width: 50, height: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Loading & Error

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Loading entry...")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
        }
        .frame(height: 120)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.yellow)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadDetail() }
            }
        }
        .padding()
        .frame(height: 160)
    }

    // MARK: - Credentials Card

    @ViewBuilder
    private func credentialsCard(_ detail: EntryDetail) -> some View {
        let hasUsername = !detail.username.isEmpty
        let hasPassword = !detail.password.isEmpty
        let hasTotp = totpCode != nil
        let hasFields = !detail.fields.isEmpty

        if hasUsername || hasPassword || hasTotp || hasFields {
            GroupCard(title: "CREDENTIALS") {
                VStack(spacing: 0) {
                    if hasUsername {
                        fieldRow(label: "Username") {
                            CopyableField(text: detail.username) {
                                Text(detail.username)
                                    .font(.system(size: 13))
                            }
                        }
                    }

                    if hasPassword {
                        if hasUsername { Divider().padding(.vertical, 6) }
                        passwordRow(detail)
                    }

                    if hasTotp, let code = totpCode {
                        if hasUsername || hasPassword { Divider().padding(.vertical, 6) }
                        totpRow(code)
                    }

                    ForEach(Array(detail.fields.enumerated()), id: \.offset) { _, field in
                        Divider().padding(.vertical, 6)
                        fieldRow(label: field.name) {
                            CopyableField(text: field.value) {
                                Text(field.value)
                                    .font(.system(size: 13))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Password Row

    private func passwordRow(_ detail: EntryDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Password")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                if !editingPassword {
                    Button {
                        editPasswordText = detail.password
                        editingPassword = true
                        editError = nil
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if editingPassword {
                TextField("Password", text: $editPasswordText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))

                HStack(spacing: 8) {
                    Button("Save") {
                        Task { await savePassword(detail) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isSaving)

                    Button("Cancel") {
                        editingPassword = false
                        editError = nil
                    }
                    .controlSize(.small)

                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let editError {
                    Text(editError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            } else {
                PasswordCopyableField(password: detail.password)
            }
        }
    }

    // MARK: - TOTP Row

    private func totpRow(_ code: String) -> some View {
        fieldRow(label: "TOTP") {
            HStack {
                CopyableField(text: code) {
                    Text(code)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .tracking(3)
                }
                Spacer()
                HStack(spacing: 4) {
                    TOTPRing(secondsRemaining: totpSecondsRemaining)
                        .frame(width: 18, height: 18)
                    Text("\(totpSecondsRemaining)s")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(totpSecondsRemaining <= 5 ? .red : .green)
                }
                .padding(.leading, 10)
            }
        }
    }

    // MARK: - Details Card

    @ViewBuilder
    private func detailsCard(_ detail: EntryDetail) -> some View {
        let hasURIs = !detail.uris.isEmpty
        let hasFolder = detail.folder != nil && !detail.folder!.isEmpty

        if hasURIs || hasFolder {
            GroupCard(title: "DETAILS") {
                VStack(spacing: 0) {
                    ForEach(Array(detail.uris.enumerated()), id: \.offset) { index, uri in
                        if index > 0 { Divider().padding(.vertical, 6) }
                        fieldRow(label: index == 0 ? "URI" : "URI \(index + 1)") {
                            CopyableField(text: uri) {
                                Text(uri)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.blue)
                                    .lineLimit(1)
                            }
                        }
                    }

                    if hasFolder {
                        if hasURIs { Divider().padding(.vertical, 6) }
                        fieldRow(label: "Folder") {
                            Text(detail.folder!)
                                .font(.system(size: 13))
                                .padding(.vertical, 2)
                                .padding(.horizontal, 4)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Notes Card

    @ViewBuilder
    private func notesCard(_ detail: EntryDetail) -> some View {
        if let notes = detail.notes, !notes.isEmpty {
            GroupCard(title: "NOTES", trailing: {
                HStack(spacing: 8) {
                    if !editingNotes {
                        Button {
                            editNotesText = notes
                            editingNotes = true
                            editError = nil
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }

                    CopyAllButton(text: notes, isCopied: $notesCopied)
                }
            }) {
                if editingNotes {
                    TextEditor(text: $editNotesText)
                        .font(.system(size: 12))
                        .frame(minHeight: 60)
                        .scrollContentBackground(.hidden)

                    HStack(spacing: 8) {
                        Button("Save") {
                            Task { await saveNotes(detail) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isSaving)

                        Button("Cancel") {
                            editingNotes = false
                            editError = nil
                        }
                        .controlSize(.small)

                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let editError {
                        Text(editError)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                } else {
                    ZStack {
                        Text(notes)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .opacity(notesCopied ? 0 : 1)
                            .animation(.easeInOut(duration: 0.2), value: notesCopied)

                        Text("Copied")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.green)
                            .opacity(notesCopied ? 1 : 0)
                            .offset(y: notesCopied ? 0 : 4)
                            .animation(.easeInOut(duration: 0.2), value: notesCopied)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            content()
        }
    }

    // MARK: - Actions

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil

        guard let loaded = await service.getEntryDetail(for: entry) else {
            errorMessage = "Failed to load entry details"
            isLoading = false
            return
        }

        detail = loaded
        isLoading = false

        // Fetch TOTP if entry has it
        if loaded.hasTotp {
            await refreshTOTP()
            startTOTPTimer()
        }
    }

    private func refreshTOTP() async {
        totpCode = await service.getTOTPCode(for: entry)
        // TOTP codes rotate every 30 seconds
        let now = Date()
        let seconds = Int(now.timeIntervalSince1970)
        totpSecondsRemaining = 30 - (seconds % 30)
    }

    private func startTOTPTimer() {
        totpTimer?.invalidate()
        totpTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                if totpSecondsRemaining <= 1 {
                    await refreshTOTP()
                } else {
                    totpSecondsRemaining -= 1
                }
            }
        }
    }

    private func savePassword(_ detail: EntryDetail) async {
        isSaving = true
        editError = nil
        let success = await service.editEntry(
            for: entry, password: editPasswordText, notes: detail.notes
        )
        isSaving = false
        if success {
            editingPassword = false
            await loadDetail()
        } else {
            editError = "Failed to save password"
        }
    }

    private func saveNotes(_ detail: EntryDetail) async {
        isSaving = true
        editError = nil
        let success = await service.editEntry(
            for: entry, password: detail.password, notes: editNotesText
        )
        isSaving = false
        if success {
            editingNotes = false
            await loadDetail()
        } else {
            editError = "Failed to save notes"
        }
    }
}

// MARK: - Group Card

private struct GroupCard<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                trailing
            }
            content
        }
        .padding(10)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Password Copyable Field (hover to reveal)

private struct PasswordCopyableField: View {
    let password: String
    @State private var isHovering = false
    @State private var showCopied = false

    var body: some View {
        Button {
            guard !showCopied else { return }
            Clipboard.copyAndClear(password)
            showCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopied = false
            }
        } label: {
            ZStack {
                Group {
                    if isHovering {
                        Text(password)
                            .font(.system(size: 13, design: .monospaced))
                    } else {
                        Text(String(repeating: "•", count: min(password.count, 16)))
                            .font(.system(size: 13, design: .monospaced))
                            .tracking(2)
                    }
                }
                .opacity(showCopied ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: showCopied)

                Text("Copied")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .opacity(showCopied ? 1 : 0)
                    .offset(y: showCopied ? 0 : 4)
                    .animation(.easeInOut(duration: 0.2), value: showCopied)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovering ? .primary.opacity(0.06) : .clear)
        )
        .onHover { isHovering = $0 }
    }
}

// MARK: - TOTP Countdown Ring

private struct TOTPRing: View {
    let secondsRemaining: Int

    private var progress: Double {
        Double(secondsRemaining) / 30.0
    }

    var body: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(
                secondsRemaining <= 5 ? Color.red : Color.green,
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .animation(.linear(duration: 1), value: secondsRemaining)
    }
}
```

- [ ] **Step 2: Verify build compiles**

Run: `cd /Users/carlopizzuto/.dotfiles/bw-menubar && swift build 2>&1`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/BWMenuBar/EntryDetailView.swift
git commit -m "feat(bw-menubar): add EntryDetailView with grouped cards, click-to-copy, inline edit"
```

---

### Task 5: Wire VaultListView — Detail Navigation + Quick-Copy

**Files:**
- Modify: `Sources/BWMenuBar/VaultListView.swift`

- [ ] **Step 1: Add selectedEntry state and detail view routing**

In `VaultListView.swift`, add a new state variable after `confirmationMessage` (line 9):

```swift
    @State private var selectedEntry: VaultEntry?
```

Replace the body's `VStack` conditional logic (lines 16-38) to include the detail view:

```swift
    var body: some View {
        VStack(spacing: 0) {
            if let selectedEntry {
                EntryDetailView(
                    entry: selectedEntry,
                    service: service,
                    isPresented: Binding(
                        get: { self.selectedEntry != nil },
                        set: { if !$0 { self.selectedEntry = nil } }
                    )
                )
            } else if showingAddEntry {
                AddEntryView(service: service, isPresented: $showingAddEntry) {
                    Task {
                        await service.loadEntries()
                        confirmationMessage = "Entry added"
                        try? await Task.sleep(for: .seconds(2))
                        if !Task.isCancelled { confirmationMessage = nil }
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

- [ ] **Step 2: Update EntryRow to support quick-copy and detail navigation**

Replace the `EntryRow` struct (lines 201-224) with a version that has a quick-copy button and calls `onSelect` for navigation:

```swift
private struct EntryRow: View {
    let entry: VaultEntry
    let onSelect: () -> Void
    let onQuickCopy: () -> Void
    @State private var showCopied = false

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    ZStack(alignment: .leading) {
                        Text(entry.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .opacity(showCopied ? 0 : 1)
                            .animation(.easeInOut(duration: 0.2), value: showCopied)

                        Text("Copied")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.green)
                            .opacity(showCopied ? 1 : 0)
                            .offset(y: showCopied ? 0 : 4)
                            .animation(.easeInOut(duration: 0.2), value: showCopied)
                    }
                    if !entry.user.isEmpty {
                        Text(entry.user)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    guard !showCopied else { return }
                    onQuickCopy()
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopied = false
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy password")
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 3: Update the list to use the new EntryRow and route clicks**

In `readyView`, update the `List` block (around lines 126-143) to use the new `EntryRow` init and route clicks to detail:

```swift
            } else {
                List(filtered) { entry in
                    EntryRow(entry: entry, onSelect: {
                        selectedEntry = entry
                    }, onQuickCopy: {
                        Task { await copyPassword(for: entry) }
                    })
                    .contextMenu {
                        Button("Copy Password") {
                            Task { await copyPassword(for: entry) }
                        }
                        Button("Copy Username") {
                            guard !entry.user.isEmpty else { return }
                            Clipboard.copyAndClear(entry.user)
                            closePopover()
                        }
                    }
                }
                .listStyle(.plain)
                .frame(maxHeight: 420)
            }
```

- [ ] **Step 4: Update copyPassword to not close popover (for quick-copy)**

The quick-copy icon should copy but NOT close the popover (the user is staying in the list). The existing `copyPassword` method calls `closePopover()`. Create a separate method or add a parameter:

Replace the `copyPassword` method (lines 186-189):

```swift
    private func copyPassword(for entry: VaultEntry) async {
        guard let password = await service.getPassword(for: entry) else { return }
        Clipboard.copyAndClear(password)
    }
```

Remove the `closePopover()` call — the detail view or context menu can handle dismissal if needed. The context menu auto-dismisses on its own.

- [ ] **Step 5: Remove the unused closePopover method if no longer needed**

Check if `closePopover()` is still referenced. If the context menu "Copy Username" was the only other caller and it works fine without explicit popover close (context menus auto-dismiss), remove the `closePopover()` method entirely. If "Copy Username" still needs it, keep it only for that context menu action:

```swift
    private func closePopover() {
        NSApp.keyWindow?.close()
    }
```

- [ ] **Step 6: Verify build compiles**

Run: `cd /Users/carlopizzuto/.dotfiles/bw-menubar && swift build 2>&1`
Expected: Build succeeds.

- [ ] **Step 7: Run full test suite**

Run: `cd /Users/carlopizzuto/.dotfiles/bw-menubar && swift test 2>&1`
Expected: All tests PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/BWMenuBar/VaultListView.swift
git commit -m "feat(bw-menubar): wire entry detail view with quick-copy in vault list"
```

---

### Task 6: Build, Install, and Manual Test

**Files:**
- No new files — manual verification

- [ ] **Step 1: Build the app**

Run: `cd /Users/carlopizzuto/.dotfiles/bw-menubar && make build 2>&1`
Expected: Build succeeds.

- [ ] **Step 2: Run the app for testing**

Run: `cd /Users/carlopizzuto/.dotfiles/bw-menubar && make run 2>&1`

Test the following:
1. Click an entry in the vault list → detail view opens with all fields
2. Click the clipboard icon on a row → password copies without opening detail, "Copied" flash on the row
3. In detail view: click username → "Copied" flash, text appears in clipboard
4. In detail view: hover password → reveals actual password
5. In detail view: click password → "Copied" flash, password in clipboard
6. In detail view: click URI → "Copied" flash
7. TOTP (if entry has one): countdown ring animates, click code to copy
8. Notes: can select text, click copy-all icon → "Copied" overlay
9. Edit password: click pencil, change password, save → refreshes
10. Edit notes: click pencil, change notes, save → refreshes
11. Back button returns to list
12. Entry with no TOTP/notes/URIs → those sections hidden

- [ ] **Step 3: Install the app**

Run: `cd /Users/carlopizzuto/.dotfiles/bw-menubar && make install 2>&1`
Expected: App installed to ~/Applications, LaunchAgent updated.

- [ ] **Step 4: Commit any fixes from manual testing**

If any fixes were needed during testing, commit them:

```bash
git add -A
git commit -m "fix(bw-menubar): fixes from manual testing of entry detail view"
```
