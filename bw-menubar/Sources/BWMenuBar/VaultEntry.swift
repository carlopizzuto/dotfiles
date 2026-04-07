// Sources/BWMenuBar/VaultEntry.swift
import Foundation

struct VaultEntry: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let user: String
    let folder: String

    /// Parse the tab-separated output of `rbw list --fields name,user,folder`.
    static func parse(rbwOutput: String) -> [VaultEntry] {
        rbwOutput
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> VaultEntry? in
                let trimmed = line.trimmingCharacters(in: .newlines)
                guard !trimmed.isEmpty else { return nil }
                let parts = trimmed.split(separator: "\t", omittingEmptySubsequences: false)
                    .map(String.init)
                let name = parts.indices.contains(0) ? parts[0] : ""
                guard !name.isEmpty else { return nil }
                let user = parts.indices.contains(1) ? parts[1] : ""
                let folder = parts.indices.contains(2) ? parts[2] : ""
                return VaultEntry(name: name, user: user, folder: folder)
            }
    }

    /// Case-insensitive match against name and user.
    func matches(query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let q = query.lowercased()
        return name.lowercased().contains(q) || user.lowercased().contains(q)
    }
}
