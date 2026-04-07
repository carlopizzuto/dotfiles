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
    /// Runs on a detached task to avoid blocking the main actor.
    private func shell(_ args: [String]) async -> (output: String, exitCode: Int32) {
        await Task.detached {
            let process = Process()
            let stdout = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = args
            process.standardOutput = stdout
            process.standardError = Pipe()

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
}
