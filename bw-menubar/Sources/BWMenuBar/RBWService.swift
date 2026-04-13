// Sources/BWMenuBar/RBWService.swift
import Foundation
import Observation

enum VaultState: Equatable {
    case loading
    case locked
    case ready
    case error(String)
}

@MainActor @Observable
final class RBWService {
    var state: VaultState = .loading
    var entries: [VaultEntry] = []

    // MARK: - Shell helper

    /// Run a command via /usr/bin/env and return (stdout, exitCode).
    /// - Parameter stdinData: Optional data written to stdin before launch.
    ///   Must be under ~64 KB (pipe buffer limit); larger payloads will deadlock.
    /// Runs on a detached task to avoid blocking the main actor.
    private func shell(_ args: [String], stdinData: Data? = nil, extraEnv: [String: String]? = nil) async -> (output: String, exitCode: Int32) {
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
            if let extraEnv {
                for (key, value) in extraEnv { env[key] = value }
            }
            process.environment = env

            // Write stdin before process.run(); safe for payloads under pipe buffer (~64 KB)
            if let stdinData {
                let stdinPipe = Pipe()
                process.standardInput = stdinPipe
                try? stdinPipe.fileHandleForWriting.write(contentsOf: stdinData)
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

    // MARK: - Vault operations

    /// Check whether rbw is installed.
    func isInstalled() async -> Bool {
        let (_, code) = await shell(["which", "rbw"])
        return code == 0
    }

    /// Check whether the vault is currently unlocked.
    func isUnlocked() async -> Bool {
        let (_, code) = await shell(["rbw", "unlocked"])
        return code == 0
    }

    /// Trigger rbw unlock (shows pinentry dialog).
    func unlock() async -> Bool {
        let (_, code) = await shell(["rbw", "unlock"])
        return code == 0
    }

    /// Background sync.
    func sync() async {
        _ = await shell(["rbw", "sync"])
    }

    /// Load all vault entries.
    func loadEntries() async {
        let (output, code) = await shell(["rbw", "list", "--fields", "name,user,folder"])
        if code == 0 {
            entries = VaultEntry.parse(rbwOutput: output)
        } else {
            entries = []
            state = .error("Failed to list vault entries")
        }
    }

    /// Retrieve password for an entry.
    func getPassword(for entry: VaultEntry) async -> String? {
        var args = ["rbw", "get"]
        if !entry.folder.isEmpty {
            args += ["--folder", entry.folder]
        }
        args.append(entry.name)
        if !entry.user.isEmpty {
            args.append(entry.user)
        }
        let (output, code) = await shell(args)
        return code == 0 ? output : nil
    }

    // MARK: - Startup flow

    /// Full startup sequence: check install → check lock → load entries.
    func startup() async {
        state = .loading

        guard await isInstalled() else {
            state = .error("rbw is not installed.\nInstall with: brew install rbw")
            return
        }

        if !(await isUnlocked()) {
            state = .locked
            return
        }

        // Sync in background, load entries immediately
        async let syncTask: () = sync()
        await loadEntries()
        _ = await syncTask

        if case .error = state { return }
        state = .ready
    }

    // MARK: - Add entry operations

    /// Password generation mode flags shared by generate commands.
    nonisolated private static func passwordModeFlags(noSymbols: Bool, onlyNumbers: Bool, diceware: Bool) -> [String] {
        var flags: [String] = []
        if noSymbols { flags.append("--no-symbols") }
        if onlyNumbers { flags.append("--only-numbers") }
        if diceware { flags.append("--diceware") }
        return flags
    }

    /// Build args for `rbw generate <length>` (preview only, no save).
    nonisolated static func generateArgs(length: Int, noSymbols: Bool, onlyNumbers: Bool, diceware: Bool) -> [String] {
        var args = ["rbw", "generate"]
        args += passwordModeFlags(noSymbols: noSymbols, onlyNumbers: onlyNumbers, diceware: diceware)
        args.append("\(length)")
        return args
    }

    /// Build args for `rbw add <name> [user]` with optional flags.
    nonisolated static func addEntryArgs(name: String, user: String, uri: String, folder: String) -> [String] {
        var args = ["rbw", "add"]
        if !uri.isEmpty { args += ["--uri", uri] }
        if !folder.isEmpty { args += ["--folder", folder] }
        args.append(name)
        if !user.isEmpty { args.append(user) }
        return args
    }

    /// Build args for `rbw generate <length> <name> [user]` with optional flags (saves entry).
    nonisolated static func generateEntryArgs(
        name: String, user: String, length: Int,
        uri: String, folder: String,
        noSymbols: Bool, onlyNumbers: Bool, diceware: Bool
    ) -> [String] {
        var args = ["rbw", "generate"]
        args += passwordModeFlags(noSymbols: noSymbols, onlyNumbers: onlyNumbers, diceware: diceware)
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

    /// Extract unique usernames from loaded entries for autocomplete.
    func listUsers() -> [String] {
        Array(Set(entries.map(\.user).filter { !$0.isEmpty })).sorted()
    }

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
        let stdinData = Data(stdin.utf8)
        let (_, code) = await shell(args, stdinData: stdinData, extraEnv: ["EDITOR": "cat"])
        return code == 0
    }
}
