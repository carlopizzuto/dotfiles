// Sources/BWMenuBar/BWMenuBarApp.swift
import SwiftUI

@main
struct BWMenuBarApp: App {
    @State private var service = RBWService()

    var body: some Scene {
        MenuBarExtra("Bitwarden", systemImage: "key.fill") {
            VaultListView(service: service)
        }
        .menuBarExtraStyle(.window)
    }
}
