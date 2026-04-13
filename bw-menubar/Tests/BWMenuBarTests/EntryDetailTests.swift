import Testing
@testable import BWMenuBar

@Suite("Entry Detail")
struct EntryDetailTests {

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
