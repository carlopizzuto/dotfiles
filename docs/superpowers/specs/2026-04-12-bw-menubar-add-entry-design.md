# BWMenuBar — Add Entry Feature

**Date:** 2026-04-12
**Scope:** Add a "new login" creation flow to the BWMenuBar macOS menubar app

## Overview

Add a + button to the vault list footer that navigates to an inline form for creating new Bitwarden login entries. Supports both manual password entry and password generation via `rbw add` and `rbw generate`.

## Constraints

- `rbw add` only supports login/password entries (not cards, identities, SSH keys, or notes)
- `rbw add` expects `$EDITOR` to write password + notes into a temp file
- `rbw generate` creates an entry and generates a password in one command
- All operations go through the `rbw` CLI — no direct Bitwarden API access

## UI Design

### Navigation

- `VaultListView` gains a `@State private var showingAddEntry = false`
- When true, `AddEntryView` renders in place of the list (full view replacement, not sheet/modal)
- The + button lives in the existing footer bar, next to the entry count and sync button
- "← Back" in the form header sets `showingAddEntry = false`

### AddEntryView — Single View with DisclosureGroup

A single SwiftUI view with progressive disclosure for password generation options.

**Fields:**

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| Name | TextField | Yes | Entry name (e.g., "GitHub") |
| Username | TextField | No | Email or username |
| Password | SecureField / TextField | No | Editable in both manual and generate modes |
| URI | TextField | No | Website URL |
| Folder | TextField | No | Autocomplete from existing folder names |

**Generate Password Toggle:**

When toggled on:
- Immediately generates a password with default settings (length 16, symbols included)
- Reveals a DisclosureGroup-style options panel containing:
  - Length slider (range 8–64, default 16; switches to 3–10 "words" for diceware)
  - Option pills: "No symbols", "Numbers only", "Diceware" (mutually exclusive behavior below)
  - "↻ Regenerate" button
- The password field remains editable — user can tweak after generation
- A copy button (clipboard icon) sits inline with the password field
- Changing length or toggling options auto-regenerates the password

**Option mutual exclusivity:**
- "No symbols" and "Numbers only" are independent toggles
- Selecting "Diceware" disables both (generates words, not characters)
- Diceware changes the length label to "WORDS" and range to 3–10 (default 5)

**Save button:**
- Disabled until Name field is non-empty
- Calls `rbw add` (manual mode) or `rbw generate` (generate mode)
- If generate is on but user edited the password manually, use `rbw add` with the edited password

### Confirmation Flow

On successful save:
1. Navigate back to vault list (`showingAddEntry = false`)
2. Trigger `loadEntries()` to refresh the list
3. Flash "Entry added" in the footer (replaces entry count for ~2 seconds, green-tinted text), then fade back to normal count

## RBWService API Additions

### New Methods

```swift
/// Add a login entry with a manual password.
/// Uses EDITOR trick: sets process env EDITOR to a script that writes
/// the password into the temp file rbw creates.
func addEntry(name: String, user: String, password: String, uri: String, folder: String) async -> Bool

/// Add a login entry with a generated password.
/// Calls: rbw generate <length> <name> [user] [--uri] [--folder] [flags]
func generateEntry(name: String, user: String, length: Int, uri: String, folder: String,
                   noSymbols: Bool, onlyNumbers: Bool, diceware: Bool) async -> Bool

/// Generate a password without saving (for form preview).
/// Calls: rbw generate <length> [flags] (no name arg = stdout only)
func generatePassword(length: Int, noSymbols: Bool, onlyNumbers: Bool, diceware: Bool) async -> String?

/// Extract unique folder names from current entries for autocomplete.
func listFolders() -> [String]
```

### shell() Enhancement

The existing `shell(_ args:)` helper needs an optional `stdinData` parameter so `addEntry` can pipe the password:

```swift
private func shell(_ args: [String], stdinData: Data? = nil) async -> (output: String, exitCode: Int32)
```

When `stdinData` is provided, set `process.standardInput` to a Pipe and write the data to it before closing.

### Stdin Password Piping

`rbw add` reads the password from stdin when not connected to a TTY (no EDITOR needed). The first line is the password:

```swift
let passwordData = password.data(using: .utf8)
await shell(["rbw", "add", name, user, "--uri", uri, "--folder", folder], stdinData: passwordData)
```

### generatePassword (preview only)

`rbw generate <length>` without a name argument outputs the generated password to stdout without saving anything. This powers the in-form preview.

## Error Handling

- **`rbw add` / `rbw generate` returns non-zero:** Show inline error text below Save button (red). Keep form populated for retry.
- **Duplicate entry name:** rbw returns an error, surface the message as-is.
- **Vault locks mid-form:** Existing `startup()` state machine handles this — the view switches to the locked state automatically.
- **Name empty:** Save button stays disabled. No error message needed.

## File Changes

| File | Change |
|------|--------|
| `Sources/BWMenuBar/AddEntryView.swift` | **New** — Form view with all fields, generate toggle, DisclosureGroup |
| `Sources/BWMenuBar/RBWService.swift` | Add `addEntry()`, `generateEntry()`, `generatePassword()`, `listFolders()` |
| `Sources/BWMenuBar/VaultListView.swift` | Add + button in footer, `showingAddEntry` state, conditional view switching, confirmation flash |
| `Tests/BWMenuBarTests/AddEntryTests.swift` | **New** — Tests for generate flag building, EDITOR script construction, folder extraction |

## Out of Scope

- Card, identity, SSH key, and note entry types (rbw CLI doesn't support creating these)
- Editing existing entries (separate feature, uses `rbw edit`)
- Deleting entries (separate feature, uses `rbw remove`)
- Notes field (could be added later as additional lines after password in the EDITOR temp file)
