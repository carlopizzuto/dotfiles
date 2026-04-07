// Sources/BWMenuBar/BWMenuBarApp.swift
import SwiftUI

@main
struct BWMenuBarApp: App {
    var body: some Scene {
        MenuBarExtra("Bitwarden", systemImage: "key.fill") {
            Text("BWMenuBar loading...")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
