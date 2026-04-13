# BWMenuBar — Entry Detail & Edit Feature

**Date:** 2026-04-12
**Scope:** Replace click-to-copy-password with a full entry detail view, supporting inline editing of password and notes.

## Overview

Clicking a vault entry opens a detail view showing all available fields (username, password, URIs, TOTP, folder, notes, custom fields) in grouped cards. Fields are click-to-copy with an animated "Copied" flash. Password is hidden by default, revealed on hover. Password and notes support inline editing via `rbw edit`. A quick-copy icon on each list row preserves the fast password-copy workflow without opening the detail view.

## Constraints

- `rbw get --raw` returns full entry JSON: id, name, username, password, totp (secret), uris, fields, notes, history
- `rbw edit` only supports modifying password and notes (line 1 = password, remaining lines = notes)
- `rbw edit` works with `EDITOR=cat` + stdin pipe — no interactive editor needed
- `rbw code` fetches the current TOTP code (separate from `--raw` which only has the secret)
- Name, username, URI, and folder are not editable via the CLI

## Navigation

- `VaultListView` gains `@State private var selectedEntry: VaultEntry?`
- When set, `EntryDetailView` renders in place of the list (same full-view-replacement pattern as `AddEntryView`)
- "Back" in the detail header sets `selectedEntry = nil`
- Each `EntryRow` gains a small clipboard icon for quick password copy without navigating to detail
- Quick-copy on row: copies password, row text briefly flashes "Copied" then returns (same animation pattern as detail fields)

## Data Model

### EntryDetail struct

Parsed from `rbw get --raw` JSON output:

```swift
struct EntryDetail {
    let id: String
    let name: String
    let username: String
    let password: String
    let uris: [String]
    let folder: String?
    let notes: String?
    let fields: [(name: String, value: String)]
    let history: [(password: String, lastUsedDate: String)]
}
```

TOTP code is fetched separately via `rbw code` and stored as `@State` in the view, refreshed on a timer.

## UI Design

### Layout: Grouped Sections

The detail view uses grouped cards on a dark background, similar to macOS system preferences panels.

**Cards:**

1. **Credentials** — username, password, TOTP (if available), custom fields (if any)
2. **Details** — URIs, folder
3. **Notes** — free-text notes area

Cards that have no data to show are hidden entirely. If all fields in a group are empty, the card does not render.

### Click-to-Copy Interaction

All copyable fields (username, password, URIs, TOTP, custom field values) use the field value itself as the click target — no separate copy icon.

**Animation:**
1. User clicks the field value
2. Field text cross-fades out (opacity 0, translateY -4px)
3. Green "Copied" text cross-fades in, centered both horizontally and vertically within the field area
4. After ~1.5 seconds, the animation reverses — "Copied" fades out, original text fades back in

All copy actions use the existing `Clipboard.copyAndClear()` (30-second auto-clear).

### Password Field

- **Default state:** shown as dots (`••••••••`)
- **Hover:** dots are replaced with the actual password (monospaced)
- **Click:** copies password to clipboard with "Copied" flash (dots remain visible during copy — no need to reveal)
- **Edit icon:** pencil icon next to the field label, triggers inline editing

### TOTP Field

- Displays the current 6-digit code in large monospaced text
- Countdown timer with a circular ring indicator and seconds remaining, separated from the clickable code area by a gap
- Click the code to copy with "Copied" flash (centered within the code area, not spanning into the timer)
- Code refreshes on a timer (poll `rbw code` periodically while the detail view is visible)

### Notes Field

- **Not click-to-copy** — text is freely selectable so the user can Cmd+C specific portions
- **Copy-all icon** (clipboard) in the section header alongside the edit pencil
- Clicking copy-all shows a centered "Copied" overlay across the entire notes text area (same animation as other fields)
- Text uses `user-select: text` for free selection

### Non-Copyable Fields

- **Folder** — displayed as static text, no click behavior, no hover effect

### Conditional Rendering

| Section | Hidden when |
|---------|------------|
| Username | empty string |
| Password | empty string |
| TOTP | `rbw code` fails or no TOTP configured |
| URIs | empty array |
| Custom fields | empty array |
| Notes | null or empty |
| Folder | null or empty |
| Entire card | all fields within it are empty |

## Inline Editing

Only password and notes are editable (the two fields `rbw edit` supports).

### Edit Flow

1. User clicks the pencil icon next to the field label
2. Field becomes an editable control: `TextField` for password (monospaced), `TextEditor` for notes
3. Save and Cancel buttons appear inline below the field
4. **Save:** calls `rbw edit` with `EDITOR=cat`, piping `"password\nnotes"` via stdin
   - When editing password: sends new password + existing notes
   - When editing notes: sends existing password + new notes
5. **On success:** field returns to view mode, entry data refreshes from `rbw get --raw`
6. **On failure:** inline red error text below the field, field stays in edit mode for retry

### rbw edit mechanism

```bash
echo -e "newpassword\nnote line 1\nnote line 2" | EDITOR=cat rbw edit [--folder FOLDER] NAME [USER]
```

The `EDITOR=cat` trick: rbw creates a temp file with current content, runs `cat` which reads from stdin and overwrites the temp file, then rbw reads the result back. Line 1 = password, remaining lines = notes. Old password is automatically archived in the entry's history.

## RBWService API Additions

### New Methods

```swift
/// Fetch full entry detail as JSON.
/// Calls: rbw get --raw [--folder FOLDER] NAME [USER]
func getEntryDetail(for entry: VaultEntry) async -> EntryDetail?

/// Fetch current TOTP code.
/// Calls: rbw code [--folder FOLDER] NAME [USER]
func getTOTPCode(for entry: VaultEntry) async -> String?

/// Edit an entry's password and/or notes.
/// Calls: EDITOR=cat rbw edit [--folder FOLDER] NAME [USER]
/// with password + notes piped via stdin.
func editEntry(for entry: VaultEntry, password: String, notes: String?) async -> Bool
```

### shell() Enhancement

The existing `shell()` helper already builds a custom `env` dictionary (for Homebrew PATH injection). The `editEntry` implementation adds `env["EDITOR"] = "cat"` to that dictionary before launching the process. No new parameters needed on `shell()` — the `EDITOR` override is internal to `editEntry`.

## Quick-Copy from Vault List

Each `EntryRow` gains a clipboard icon button on the trailing edge:
- Tapping it copies the password directly (existing `getPassword` flow) without opening the detail view
- The entry name text on that row briefly flashes to "Copied" then returns (same cross-fade animation as detail fields)
- Tapping the row itself (anywhere except the icon) navigates to the detail view

## Error Handling

- **`rbw get --raw` fails:** Show error state in detail view with retry option
- **`rbw code` fails:** TOTP section simply doesn't render (entry may not have TOTP)
- **`rbw edit` fails:** Inline red error text below the edited field, field stays in edit mode
- **Vault locks mid-view:** Existing `startup()` state machine handles this — view switches to locked state

## File Changes

| File | Change |
|------|--------|
| `Sources/BWMenuBar/EntryDetailView.swift` | **New** — Detail view with grouped cards, click-to-copy, hover-reveal, inline editing |
| `Sources/BWMenuBar/RBWService.swift` | Add `EntryDetail` struct, `getEntryDetail()`, `getTOTPCode()`, `editEntry()` methods |
| `Sources/BWMenuBar/VaultListView.swift` | Add `selectedEntry` state, quick-copy icon on rows, conditional routing to detail view |
| `Tests/BWMenuBarTests/EntryDetailTests.swift` | **New** — Tests for JSON parsing, edit arg building |

## Out of Scope

- Deleting entries (`rbw remove` — separate feature)
- Editing name, username, URI, or folder (not supported by `rbw edit`)
- Password history display (data is available in `--raw` but not needed for v1)
- Opening URIs in browser (could be added later)
