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
